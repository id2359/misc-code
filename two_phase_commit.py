"""
Two-Phase Commit (2PC) with Kazoo (ZooKeeper)

ZNode layout:
  /2pc/<txn_id>/                  - transaction root (ephemeral)
  /2pc/<txn_id>/votes/<pid>       - participant vote: "yes" | "no"
  /2pc/<txn_id>/decision          - coordinator decision: "commit" | "abort"

Sequence:
  Phase 1 (Voting):    Coordinator asks all participants to vote.
  Phase 2 (Decision):  Coordinator tallies votes, writes decision; participants act.
"""

import threading
import time
import uuid
import logging
from enum import Enum
from typing import Callable

from kazoo.client import KazooClient
from kazoo.exceptions import NodeExistsError, NoNodeError
from kazoo.recipe.barrier import Barrier

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s")


class Vote(str, Enum):
    YES = "yes"
    NO = "no"


class Decision(str, Enum):
    COMMIT = "commit"
    ABORT = "abort"


TXN_ROOT = "/2pc"


# ---------------------------------------------------------------------------
# Coordinator
# ---------------------------------------------------------------------------

class Coordinator:
    """
    Drives 2PC for a given transaction.

    Usage:
        coord = Coordinator(zk, txn_id, participants=["p1", "p2"])
        decision = coord.run(timeout=10.0)
    """

    def __init__(self, zk: KazooClient, txn_id: str, participants: list[str]):
        self.zk = zk
        self.txn_id = txn_id
        self.participants = participants
        self.log = logging.getLogger(f"Coordinator[{txn_id[:8]}]")

        self._txn_path = f"{TXN_ROOT}/{txn_id}"
        self._votes_path = f"{self._txn_path}/votes"
        self._decision_path = f"{self._txn_path}/decision"

    def run(self, timeout: float = 10.0) -> Decision:
        self._setup_znodes()
        decision = self._collect_votes(timeout)
        self._write_decision(decision)
        self.log.info("Decision written: %s", decision.value)
        return decision

    def _setup_znodes(self):
        self.zk.ensure_path(TXN_ROOT)
        # Ephemeral=False so participants can still read decision after coordinator
        # reconnects; use persistent for the transaction root.
        self.zk.ensure_path(self._txn_path)
        self.zk.ensure_path(self._votes_path)

    def _collect_votes(self, timeout: float) -> Decision:
        """
        Block until all participants have voted or timeout expires.
        Returns ABORT on timeout or any NO vote.
        """
        ready = threading.Event()
        expected = set(self.participants)

        def _check_votes():
            try:
                children = self.zk.get_children(self._votes_path)
            except NoNodeError:
                return
            if expected.issubset(set(children)):
                ready.set()

        # Watch for new vote children
        @self.zk.ChildrenWatch(self._votes_path)
        def _vote_watcher(children):
            self.log.info("Votes so far: %s", children)
            if expected.issubset(set(children)):
                ready.set()
            return True  # keep watch alive

        _check_votes()  # handle votes that already arrived

        if not ready.wait(timeout):
            self.log.warning("Timeout waiting for votes — aborting")
            return Decision.ABORT

        # Tally
        for pid in self.participants:
            vote_path = f"{self._votes_path}/{pid}"
            try:
                data, _ = self.zk.get(vote_path)
                vote = data.decode()
                self.log.info("Vote from %s: %s", pid, vote)
                if vote == Vote.NO:
                    return Decision.ABORT
            except NoNodeError:
                self.log.warning("Missing vote from %s — aborting", pid)
                return Decision.ABORT

        return Decision.COMMIT

    def _write_decision(self, decision: Decision):
        try:
            self.zk.create(self._decision_path, decision.value.encode())
        except NodeExistsError:
            self.zk.set(self._decision_path, decision.value.encode())

    def cleanup(self):
        """Remove all transaction znodes."""
        self.zk.delete(self._txn_path, recursive=True)


# ---------------------------------------------------------------------------
# Participant
# ---------------------------------------------------------------------------

class Participant:
    """
    Participant in a 2PC transaction.

    Usage:
        p = Participant(zk, txn_id, pid="worker-1",
                        prepare_fn=my_prepare, commit_fn=my_commit, abort_fn=my_abort)
        p.run()
    """

    def __init__(
        self,
        zk: KazooClient,
        txn_id: str,
        pid: str,
        prepare_fn: Callable[[], bool],
        commit_fn: Callable[[], None],
        abort_fn: Callable[[], None],
        decision_timeout: float = 15.0,
    ):
        self.zk = zk
        self.txn_id = txn_id
        self.pid = pid
        self.prepare_fn = prepare_fn
        self.commit_fn = commit_fn
        self.abort_fn = abort_fn
        self.decision_timeout = decision_timeout
        self.log = logging.getLogger(f"Participant[{pid}]")

        self._votes_path = f"{TXN_ROOT}/{txn_id}/votes"
        self._decision_path = f"{TXN_ROOT}/{txn_id}/decision"
        self._vote_path = f"{self._votes_path}/{pid}"

    def run(self):
        # Phase 1: prepare and cast vote
        vote = self._phase1_vote()
        self._cast_vote(vote)

        # Phase 2: wait for coordinator decision
        decision = self._phase2_await_decision()

        if decision == Decision.COMMIT:
            self.log.info("Committing")
            self.commit_fn()
        else:
            self.log.info("Aborting")
            self.abort_fn()

    def _phase1_vote(self) -> Vote:
        self.log.info("Running prepare")
        try:
            ok = self.prepare_fn()
            vote = Vote.YES if ok else Vote.NO
        except Exception as exc:
            self.log.error("prepare_fn raised %s — voting NO", exc)
            vote = Vote.NO
        self.log.info("Voting %s", vote.value)
        return vote

    def _cast_vote(self, vote: Vote):
        self.zk.ensure_path(self._votes_path)
        try:
            self.zk.create(self._vote_path, vote.value.encode(), ephemeral=True)
        except NodeExistsError:
            self.zk.set(self._vote_path, vote.value.encode())

    def _phase2_await_decision(self) -> Decision:
        """
        Watch the decision znode.  If the coordinator crashes, the ephemeral
        transaction root disappears and we abort (heuristic; real systems use
        a persistent coordinator log).
        """
        ready = threading.Event()
        result: list[Decision] = []

        def _on_decision(data, stat, event=None):
            if data is not None:
                result.append(Decision(data.decode()))
                ready.set()

        # DataWatch fires immediately with current value if node exists
        self.zk.DataWatch(self._decision_path, _on_decision)

        if not ready.wait(self.decision_timeout):
            self.log.warning("Timeout waiting for decision — aborting (heuristic)")
            return Decision.ABORT

        return result[0]


# ---------------------------------------------------------------------------
# Demo
# ---------------------------------------------------------------------------

def run_demo():
    zk = KazooClient(hosts="127.0.0.1:2181")
    zk.start()

    txn_id = str(uuid.uuid4())
    participants = ["worker-1", "worker-2", "worker-3"]

    print(f"\n{'='*60}")
    print(f"Transaction: {txn_id[:8]}")
    print(f"{'='*60}\n")

    # --- spin up participants in threads ---
    def make_participant(pid: str, will_vote_yes: bool):
        p_zk = KazooClient(hosts="127.0.0.1:2181")
        p_zk.start()
        p = Participant(
            zk=p_zk,
            txn_id=txn_id,
            pid=pid,
            prepare_fn=lambda: will_vote_yes,
            commit_fn=lambda: print(f"  [{pid}] ✓ committed"),
            abort_fn=lambda: print(f"  [{pid}] ✗ aborted"),
        )
        p.run()
        p_zk.stop()

    votes = [True, True, True]   # change one to False to see abort path
    threads = [
        threading.Thread(target=make_participant, args=(pid, vote), daemon=True)
        for pid, vote in zip(participants, votes)
    ]
    for t in threads:
        t.start()

    time.sleep(0.5)  # let participants register their watches

    # --- run coordinator ---
    coord = Coordinator(zk, txn_id, participants)
    decision = coord.run(timeout=10.0)
    print(f"\nFinal decision: {decision.value.upper()}\n")

    for t in threads:
        t.join(timeout=5)

    coord.cleanup()
    zk.stop()


if __name__ == "__main__":
    run_demo()
