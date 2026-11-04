# bar.exs — a concurrent bar simulation in Elixir, inspired by the classic
# occam-pi bar example (drinkers, glasses, bottles, bar staff).
#
# Every entity in the bar is its own lightweight process. They share NOTHING;
# they only send each other messages — just like occam-pi channels.

defmodule Log do
  @start System.monotonic_time(:millisecond)

  def log(who, color, msg) do
    t = System.monotonic_time(:millisecond) - @start
    mm = t |> div(60_000) |> Integer.to_string() |> String.pad_leading(2, "0")
    ss = t |> rem(60_000) |> div(1000) |> Integer.to_string() |> String.pad_leading(2, "0")
    d  = t |> rem(1000) |> div(100)
    IO.puts("\e[#{color}m[#{mm}:#{ss}.#{d}] #{who}: #{msg}\e[0m")
  end
end

defmodule Sim do
  # Non-blocking check for a :closing message sitting in our mailbox.
  def closing? do
    receive do
      :closing -> :closed
    after
      0 -> :open
    end
  end
end

# GlassPool: a finite supply of clean glasses. Drinkers block when empty.
# The ONLY way glasses come back is when Staff finishes washing one.
defmodule GlassPool do
  def start(n), do: spawn(fn -> loop(n, []) end)

  defp loop(clean, waiting) do
    receive do
      {:acquire, from} ->
        if clean > 0 do
          send(from, :glass_ok)
          loop(clean - 1, waiting)
        else
          if waiting == [],
            do: Log.log("Glasses", 90, "out of clean glasses! Drinkers are waiting...")
          loop(clean, waiting ++ [from])
        end

      :release ->
        case waiting do
          [] -> loop(clean + 1, waiting)
          [next | rest] ->
            send(next, :glass_ok)
            loop(clean, rest)
        end
    end
  end
end

# Tray: where finished drinkers dump empty glasses, and where Staff picks
# them up. Decouples drinkers from staff — nobody blocks on anybody directly.
defmodule Tray do
  def start, do: spawn(fn -> loop(0, []) end)

  defp loop(count, waiting_staff) do
    receive do
      :put ->
        case waiting_staff do
          []            -> loop(count + 1, waiting_staff)
          [next | rest] -> send(next, :ok_glass); loop(count, rest)
        end

      {:collect, from} ->
        if count > 0 do
          send(from, :ok_glass)
          loop(count - 1, waiting_staff)
        else
          loop(count, waiting_staff ++ [from])
        end
    end
  end
end

# Fridge: bottles in, bottles out. Staff watches the level and restocks.
defmodule Fridge do
  def start(n), do: spawn(fn -> loop(n) end)

  defp loop(bottles) do
    receive do
      {:take, from} ->
        if bottles > 0 do
          send(from, {:bottle, bottles - 1})
          loop(bottles - 1)
        else
          send(from, :empty)
          loop(bottles)
        end

      {:level, from} -> send(from, {:level, bottles}); loop(bottles)
      {:restock, n}  -> loop(bottles + n)
    end
  end
end

# Drinker: get glass -> get bottle -> pour -> drink -> dump glass on tray.
# Blocks honestly on every scarce resource, just like a real customer.
defmodule Drinker do
  @names ~w(Alice Bob Carol Dave Erin Frank Grace Henry Ivy Jack Kate Liam Mia Noah Olivia Pete)

  def start_all(n, glasses, tray, fridge, stats) do
    for i <- 1..n do
      base = Enum.at(@names, rem(i - 1, length(@names)))
      name = if i > length(@names), do: "#{base}##{div(i - 1, length(@names)) + 1}", else: base
      spawn(fn -> loop(name, glasses, tray, fridge, stats) end)
    end
  end

  defp loop(name, glasses, tray, fridge, stats) do
    case Sim.closing?() do
      :closed ->
        Log.log(name, 36, "heading home. Great evening!")

      :open ->
        Log.log(name, 36, "fancies a beer")
        send(glasses, {:acquire, self()})

        receive do
          :glass_ok -> :ok
          :closing  -> Log.log(name, 36, "never got a glass - going home"); exit(:normal)
        end

        await_bottle(name, fridge)

        Log.log(name, 32, "pours a beer")
        Process.sleep(300)
        Log.log(name, 32, "drinking")
        Process.sleep(:rand.uniform(2_000) + 800)   # 0.8 - 2.8 s

        send(tray, :put)
        send(stats, {:drank, name})
        Log.log(name, 32, "finished - glass goes on the tray")

        maybe_chat(name)
        loop(name, glasses, tray, fridge, stats)
    end
  end

  defp await_bottle(name, fridge) do
    send(fridge, {:take, self()})
    receive do
      {:bottle, left} ->
        Log.log(name, 36, "got a bottle (#{left} left in the fridge)")
      :empty ->
        Log.log(name, 31, "fridge is EMPTY?! Complains loudly at the bar...")
        Process.sleep(400)
        await_bottle(name, fridge)
    end
  end

  defp maybe_chat(name) do
    if :rand.uniform(10) <= 3 do
      Log.log(name, 36, "chats with friends")
      Process.sleep(:rand.uniform(1_200) + 300)
    end
  end
end

# Staff: the unsung heroes. Collect empties from the tray, wash them, return
# them to the pool; keep an eye on the fridge and haul up more bottles.
defmodule Staff do
  def start(glasses, tray, fridge, stats), do: spawn(fn -> loop(glasses, tray, fridge, stats) end)

  defp loop(glasses, tray, fridge, stats) do
    send(tray, {:collect, self()})

    receive do
      :ok_glass ->
        Log.log("Staff", 35, "picks up an empty, washes it")
        Process.sleep(700)
        send(glasses, :release)
        send(stats, :washed)
        loop(glasses, tray, fridge, stats)

      :closing ->
        Log.log("Staff", 35, "last glass washed - wiping down the bar. Good night!")

    after
      # No empties right now - use the time to check the fridge instead.
      600 ->
        send(fridge, {:level, self()})
        receive do
          {:level, level} when level < 4 -> restock(fridge, level)
          {:level, _}                    -> :ok
          :closing                       -> Log.log("Staff", 35, "wiping down the bar. Good night!")
                                            exit(:normal)
        after
          500 -> :ok   # fridge didn't answer in time; carry on
        end
        loop(glasses, tray, fridge, stats)
    end
  end

  defp restock(fridge, level) do
    need = 12 - level
    Log.log("Staff", 35, "fridge is low (#{level}) - hauling up #{need} bottles from the cellar")
    Process.sleep(300 * need)
    send(fridge, {:restock, need})
    Log.log("Staff", 35, "fridge restocked")
  end
end

# Stats: quietly counts everything that happens.
defmodule Stats do
  def start, do: spawn(fn -> loop(%{}, 0) end)

  defp loop(drinks, washed) do
    receive do
      {:drank, name}  -> loop(Map.update(drinks, name, 1, & &1 + 1), washed)
      :washed         -> loop(drinks, washed + 1)
      {:report, from} -> send(from, {:stats, drinks, washed}); loop(drinks, washed)
    end
  end

  def report(pid) do
    send(pid, {:report, self()})
    receive do
      {:stats, drinks, washed} ->
        total = drinks |> Map.values() |> Enum.sum()
        IO.puts("\n========== TONIGHT AT THE BAR ==========")
        drinks
        |> Enum.sort_by(fn {_, v} -> -v end)
        |> Enum.each(fn {k, v} ->
          IO.puts("  #{String.pad_trailing(k, 10)} beer(s) drunk: #{v}")
        end)
        IO.puts("  --------------------------------------")
        IO.puts("  #{total} beers sold, #{washed} glasses washed")
    end
  end
end

# The bar itself: open the doors, run the evening, call last orders.
defmodule Bar do
  def run(n_drinkers, open_ms) do
    stats   = Stats.start()
    glasses = GlassPool.start(5)
    tray    = Tray.start()
    fridge  = Fridge.start(12)
    staff   = Staff.start(glasses, tray, fridge, stats)
    drinkers = Drinker.start_all(n_drinkers, glasses, tray, fridge, stats)

    Log.log("Bar", 33, "OPEN! #{n_drinkers} drinkers, 5 glasses, 12 bottles in the fridge.")
    Process.sleep(open_ms)

    Log.log("Bar", 33, "LAST CALL!")
    Enum.each(drinkers, &send(&1, :closing))
    Process.sleep(4_500)   # let everyone finish their current drink
    send(staff, :closing)
    Process.sleep(1_500)

    Stats.report(stats)
  end
end

Bar.run(
  String.to_integer(System.get_env("DRINKERS") || "8"),
  String.to_integer(System.get_env("MS") || "20000")
)
