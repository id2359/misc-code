(* This program simulates SU(GROUP) lattice gauge fields with the
   simple Wilson action.
   Converted to OCaml from Creutz's C++ puregauge.cc
*)

let group = 2
let dim = 4
let size = 8
let hits = 10
let beta = ref 2.3

type matrix = {
  real : float array array;
  imag : float array array;
}

let create_matrix () =
  {
    real = Array.make_matrix group group 0.0;
    imag = Array.make_matrix group group 0.0;
  }

let copy_matrix src dst =
  for i = 0 to group - 1 do
    for j = 0 to group - 1 do
      dst.real.(i).(j) <- src.real.(i).(j);
      dst.imag.(i).(j) <- src.imag.(i).(j)
    done
  done

let set_identity m x =
  for i = 0 to group - 1 do
    for j = 0 to group - 1 do
      m.real.(i).(j) <- (if i = j then x else 0.0);
      m.imag.(i).(j) <- 0.0
    done
  done

let mat_mul_tmp = create_matrix ()

let mat_mul lhs rhs res =
  for i = 0 to group - 1 do
    for j = 0 to group - 1 do
      mat_mul_tmp.real.(i).(j) <- 0.0;
      mat_mul_tmp.imag.(i).(j) <- 0.0;
      for k = 0 to group - 1 do
        mat_mul_tmp.real.(i).(j) <- mat_mul_tmp.real.(i).(j) +. (lhs.real.(i).(k) *. rhs.real.(k).(j) -. lhs.imag.(i).(k) *. rhs.imag.(k).(j));
        mat_mul_tmp.imag.(i).(j) <- mat_mul_tmp.imag.(i).(j) +. (lhs.real.(i).(k) *. rhs.imag.(k).(j) +. lhs.imag.(i).(k) *. rhs.real.(k).(j))
      done
    done
  done;
  copy_matrix mat_mul_tmp res

let mat_add lhs rhs res =
  for i = 0 to group - 1 do
    for j = 0 to group - 1 do
      res.real.(i).(j) <- lhs.real.(i).(j) +. rhs.real.(i).(j);
      res.imag.(i).(j) <- lhs.imag.(i).(j) +. rhs.imag.(i).(j)
    done
  done

let conjugate src dst =
  for i = 0 to group - 1 do
    for j = 0 to group - 1 do
      dst.real.(i).(j) <- src.real.(j).(i);
      dst.imag.(i).(j) <- -. src.imag.(j).(i)
    done
  done

let project m =
  let nmax = group - (if group < 4 then 1 else 0) in
  for i = 0 to nmax - 1 do
    let temp = ref (m.real.(i).(0) *. m.real.(i).(0) +. m.imag.(i).(0) *. m.imag.(i).(0)) in
    for j = 1 to group - 1 do
      temp := !temp +. m.real.(i).(j) *. m.real.(i).(j) +. m.imag.(i).(j) *. m.imag.(i).(j)
    done;
    let inv_norm = 1.0 /. sqrt !temp in
    for j = 0 to group - 1 do
      m.real.(i).(j) <- m.real.(i).(j) *. inv_norm;
      m.imag.(i).(j) <- m.imag.(i).(j) *. inv_norm
    done;
    for k = i + 1 to nmax - 1 do
      let adotbr = ref (m.real.(i).(0) *. m.real.(k).(0) +. m.imag.(i).(0) *. m.imag.(k).(0)) in
      let adotbi = ref (m.real.(i).(0) *. m.imag.(k).(0) -. m.imag.(i).(0) *. m.real.(k).(0)) in
      for j = 1 to group - 1 do
        adotbr := !adotbr +. m.real.(i).(j) *. m.real.(k).(j) +. m.imag.(i).(j) *. m.imag.(k).(j);
        adotbi := !adotbi +. m.real.(i).(j) *. m.imag.(k).(j) -. m.imag.(i).(j) *. m.real.(k).(j)
      done;
      for j = 0 to group - 1 do
        m.real.(k).(j) <- m.real.(k).(j) -. (!adotbr *. m.real.(i).(j) -. !adotbi *. m.imag.(i).(j));
        m.imag.(k).(j) <- m.imag.(k).(j) -. (!adotbr *. m.imag.(i).(j) +. !adotbi *. m.real.(i).(j))
      done
    done
  done;
  if group = 2 then begin
    m.real.(1).(0) <- -. m.real.(0).(1);
    m.real.(1).(1) <- m.real.(0).(0);
    m.imag.(1).(0) <- m.imag.(0).(1);
    m.imag.(1).(1) <- -. m.imag.(0).(0)
  end

(* 48-bit LCG matching drand48 *)
let rng_state = ref 0L

let srand48 seed =
  let s = Int64.of_int seed in
  let s_shifted = Int64.shift_left s 16 in
  rng_state := Int64.logor s_shifted 0x330EL

let drand48 () =
  let a = 0x5DEECE66DL in
  let c = 0xBL in
  let mask = 0xFFFFFFFFFFFFL in
  let next_state = Int64.logand (Int64.add (Int64.mul a !rng_state) c) mask in
  rng_state := next_state;
  (Int64.to_float next_state) /. 281474976710656.0

let shape = Array.make dim size
let shift = Array.make dim 0
let nsites = size * size * size * size
let nlinks = dim * nsites
let vectorlength = nsites / 2

let ulinks = Array.init nlinks (fun _ -> create_matrix ())
let parity = Array.make nsites 0
let table1 = Array.init vectorlength (fun _ -> create_matrix ())
let table2 = Array.init vectorlength (fun _ -> create_matrix ())
let mtemp = Array.init 5 (fun _ -> Array.init vectorlength (fun _ -> create_matrix ()))
let sold = Array.make vectorlength 0.0
let snew = Array.make vectorlength 0.0
let accepted = Array.make vectorlength 0
let myindex = Array.make vectorlength 0

let cleanup msg =
  print_endline msg;
  exit 0

let split x s =
  let temp = ref s in
  if !temp < 0 || !temp >= nsites then cleanup "bad split";
  for i = dim - 1 downto 1 do
    x.(i) <- 0;
    while !temp >= shift.(i) do
      temp := !temp - shift.(i);
      x.(i) <- x.(i) + 1
    done
  done;
  x.(0) <- !temp

let siteindex x =
  let res = ref 0 in
  for i = 0 to dim - 1 do
    res := !res + shift.(i) * x.(i)
  done;
  !res

let vshift n x =
  let y = Array.make dim 0 in
  split y n;
  for i = 0 to dim - 1 do
    if x.(i) <> 0 then begin
      y.(i) <- y.(i) + x.(i);
      while y.(i) >= shape.(i) do y.(i) <- y.(i) - shape.(i) done;
      while y.(i) < 0 do y.(i) <- y.(i) + shape.(i) done
    end
  done;
  siteindex y

let ishift n dir dist =
  let x = Array.make dim 0 in
  x.(dir) <- dist;
  vshift n x

let makeindex n ind =
  let x = Array.make dim 0 in
  split x n;
  let site = ref 0 in
  for iv = 0 to vectorlength - 1 do
    while parity.(!site) <> 0 do
      incr site
    done;
    ind.(iv) <- vshift !site x;
    incr site
  done

let vgroup g =
  for iv = 0 to vectorlength - 1 do
    project g.(iv)
  done

let vcopy g1 g2 =
  for iv = 0 to vectorlength - 1 do
    copy_matrix g1.(iv) g2.(iv)
  done

let vprod g1 g2 g3 =
  for iv = 0 to vectorlength - 1 do
    mat_mul g1.(iv) g2.(iv) g3.(iv)
  done

let vsum g1 g2 g3 =
  for i = 0 to group - 1 do
    for j = 0 to group - 1 do
      for iv = 0 to vectorlength - 1 do
        g3.(iv).real.(i).(j) <- g1.(iv).real.(i).(j) +. g2.(iv).real.(i).(j);
        g3.(iv).imag.(i).(j) <- g1.(iv).imag.(i).(j) +. g2.(iv).imag.(i).(j)
      done
    done
  done

let vtprod g1 g2 s =
  for iv = 0 to vectorlength - 1 do
    s.(iv) <- 0.0
  done;
  for i = 0 to group - 1 do
    for j = 0 to group - 1 do
      for iv = 0 to vectorlength - 1 do
        s.(iv) <- s.(iv) +. (g1.(iv).real.(i).(j) *. g2.(iv).real.(j).(i) -. g1.(iv).imag.(i).(j) *. g2.(iv).imag.(j).(i))
      done
    done
  done

let vtrace g s =
  for iv = 0 to vectorlength - 1 do
    s.(iv) <- g.(iv).real.(0).(0)
  done;
  for i = 1 to group - 1 do
    for iv = 0 to vectorlength - 1 do
      s.(iv) <- s.(iv) +. g.(iv).real.(i).(i)
    done
  done

let getlinks g lattice site link =
  makeindex site myindex;
  let sft = nsites * link in
  for iv = 0 to vectorlength - 1 do
    copy_matrix lattice.(myindex.(iv) + sft) g.(iv)
  done

let getconjugate g lattice site link =
  makeindex site myindex;
  let sft = nsites * link in
  for iv = 0 to vectorlength - 1 do
    conjugate lattice.(myindex.(iv) + sft) g.(iv)
  done

let savelinks g lattice site link =
  makeindex site myindex;
  let sft = nsites * link in
  for iv = 0 to vectorlength - 1 do
    copy_matrix g.(iv) lattice.(myindex.(iv) + sft)
  done

let metro old trial bias =
  let expdeltas = ref 0.0 in
  for iv = 0 to vectorlength - 1 do
    let temp = exp (bias *. (snew.(iv) -. sold.(iv))) in
    expdeltas := !expdeltas +. temp;
    accepted.(iv) <- (if drand48 () < temp then 1 else 0)
  done;
  for iv = 0 to vectorlength - 1 do
    if accepted.(iv) <> 0 then begin
      sold.(iv) <- snew.(iv);
      copy_matrix trial.(iv) old.(iv)
    end
  done;
  !expdeltas /. (float_of_int vectorlength)

let ranmat g =
  let index = ref (int_of_float ((float_of_int vectorlength) *. drand48 ())) in
  for iv = 0 to vectorlength - 1 do
    if !index >= vectorlength then index := !index - vectorlength;
    if drand48 () < 0.5 then
      copy_matrix table1.(!index) g.(iv)
    else
      conjugate table1.(!index) g.(iv);
    incr index
  done

let vtable () =
  ranmat mtemp.(0);
  vprod table2 mtemp.(0) table1;
  vtrace table2 sold;
  vtrace table1 snew;
  ignore (metro table2 table1 (6.0 *. !beta /. (float_of_int group)));
  vcopy table2 table1;
  vcopy mtemp.(0) table2;
  vgroup table1

let maketable () =
  let temporary1 = create_matrix () in
  let temporary2 = create_matrix () in
  for iv = 0 to vectorlength - 1 do
    set_identity temporary1 (!beta /. (float_of_int group));
    set_identity temporary2 (!beta /. (float_of_int group));
    for i = 0 to group - 1 do
      for j = 0 to group - 1 do
        temporary1.real.(i).(j) <- temporary1.real.(i).(j) +. drand48 () -. 0.5;
        temporary1.imag.(i).(j) <- temporary1.imag.(i).(j) +. drand48 () -. 0.5;
        temporary2.real.(i).(j) <- temporary2.real.(i).(j) +. drand48 () -. 0.5;
        temporary2.imag.(i).(j) <- temporary2.imag.(i).(j) +. drand48 () -. 0.5
      done
    done;
    copy_matrix temporary1 table1.(iv);
    copy_matrix temporary2 table2.(iv)
  done;
  vgroup table1;
  vgroup table2;
  for i = 0 to 49 do
    vtable ()
  done

let staple st lat site link =
  for iv = 0 to vectorlength - 1 do
    set_identity st.(iv) 0.0
  done;
  let site1 = ishift site link 1 in
  for link1 = 0 to dim - 1 do
    if link1 <> link then begin
      let site2 = ishift site link1 1 in
      let site4 = ishift site1 link1 (-1) in
      let site5 = ishift site link1 (-1) in

      getlinks mtemp.(0) lat site1 link1;
      getconjugate mtemp.(1) lat site2 link;
      vprod mtemp.(0) mtemp.(1) mtemp.(2);
      getconjugate mtemp.(0) lat site link1;
      vprod mtemp.(2) mtemp.(0) mtemp.(1);
      vsum st mtemp.(1) st;

      getconjugate mtemp.(0) lat site4 link1;
      getconjugate mtemp.(1) lat site5 link;
      vprod mtemp.(0) mtemp.(1) mtemp.(2);
      getlinks mtemp.(0) lat site5 link1;
      vprod mtemp.(2) mtemp.(0) mtemp.(1);
      vsum st mtemp.(1) st
    end
  done

let monte lattice =
  vtable ();
  let stot = ref 0.0 in
  let eds = ref 0.0 in
  let iacc = ref 0 in
  for color = 0 to 1 do
    for link = 0 to dim - 1 do
      staple mtemp.(4) lattice color link;
      getlinks mtemp.(0) lattice color link;
      vtprod mtemp.(0) mtemp.(4) sold;
      for hit = 0 to hits - 1 do
        ranmat mtemp.(1);
        vprod mtemp.(0) mtemp.(1) mtemp.(2);
        vtprod mtemp.(2) mtemp.(4) snew;
        eds := !eds +. metro mtemp.(0) mtemp.(2) (!beta /. (float_of_int group));
        for iv = 0 to vectorlength - 1 do
          iacc := !iacc + accepted.(iv);
          stot := !stot +. sold.(iv)
        done
      done;
      savelinks mtemp.(0) lattice color link
    done
  done;
  let stot_val = !stot /. (2.0 *. (float_of_int (dim - 1)) *. (float_of_int nlinks) *. (float_of_int group) *. (float_of_int hits)) in
  let acc_val = (float_of_int !iacc) /. ((float_of_int nlinks) *. (float_of_int hits)) in
  let eds_val = !eds /. (2.0 *. (float_of_int dim) *. (float_of_int hits)) in
  Printf.printf "stot=%f, acc=%f, eds=%f\n%!" stot_val acc_val eds_val;
  stot_val

let overrelax lattice =
  if group > 3 then cleanup "overrelax needs GROUP<=3 or more temporaries";
  let stot = ref 0.0 in
  let eds = ref 0.0 in
  let iacc = ref 0 in
  for color = 0 to 1 do
    for link = 0 to dim - 1 do
      staple mtemp.(4) lattice color link;
      getlinks mtemp.(0) lattice color link;
      vcopy mtemp.(4) mtemp.(1);
      vgroup mtemp.(1);
      vprod mtemp.(0) mtemp.(1) mtemp.(2);
      vprod mtemp.(1) mtemp.(2) mtemp.(3);
      for iv = 0 to vectorlength - 1 do
        conjugate mtemp.(3).(iv) mtemp.(2).(iv)
      done;
      vtprod mtemp.(0) mtemp.(4) sold;
      vtprod mtemp.(2) mtemp.(4) snew;
      eds := !eds +. metro mtemp.(0) mtemp.(2) (!beta /. (float_of_int group));
      for iv = 0 to vectorlength - 1 do
        iacc := !iacc + accepted.(iv);
        stot := !stot +. sold.(iv)
      done;
      savelinks mtemp.(0) lattice color link
    done
  done;
  let stot_val = !stot /. (2.0 *. (float_of_int (dim - 1)) *. (float_of_int nlinks) *. (float_of_int group)) in
  let acc_val = (float_of_int !iacc) /. (float_of_int nlinks) in
  let eds_val = !eds /. (2.0 *. (float_of_int dim)) in
  Printf.printf "stot=%f, acc=%f, eds=%f\n%!" stot_val acc_val eds_val;
  stot_val

let renorm l =
  for octant = 0 to 2 * dim - 1 do
    let link = octant * vectorlength in
    for iv = 0 to vectorlength - 1 do
      project l.(link + iv)
    done
  done

let loop u x y =
  let count = ref 0 in
  let result = ref 0.0 in
  for color = 0 to 1 do
    for link1 = 0 to dim - 1 do
      let start_link2 = if x = y then link1 + 1 else 0 in
      for link2 = start_link2 to dim - 1 do
        if link1 <> link2 then begin
          incr count;
          let corner = ref (ishift color link1 x) in
          corner := ishift !corner link2 y;
          for iv = 0 to vectorlength - 1 do
            set_identity mtemp.(0).(iv) 1.0;
            set_identity mtemp.(1).(iv) 1.0;
            set_identity mtemp.(2).(iv) 1.0;
            set_identity mtemp.(3).(iv) 1.0
          done;
          for i = 0 to x - 1 do
            getlinks mtemp.(4) u (ishift color link1 i) link1;
            vprod mtemp.(0) mtemp.(4) mtemp.(0);
            getconjugate mtemp.(4) u (ishift !corner link1 (-i - 1)) link1;
            vprod mtemp.(2) mtemp.(4) mtemp.(2)
          done;
          for i = 0 to y - 1 do
            getlinks mtemp.(4) u (ishift !corner link2 (i - y)) link2;
            vprod mtemp.(1) mtemp.(4) mtemp.(1);
            getconjugate mtemp.(4) u (ishift color link2 (y - i - 1)) link2;
            vprod mtemp.(3) mtemp.(4) mtemp.(3)
          done;
          vprod mtemp.(0) mtemp.(1) mtemp.(0);
          vprod mtemp.(0) mtemp.(2) mtemp.(0);
          vtprod mtemp.(0) mtemp.(3) sold;
          for iv = 0 to vectorlength - 1 do
            result := !result +. sold.(iv)
          done
        end
      done
    done
  done;
  let res_val = !result /. ((float_of_int group) *. (float_of_int vectorlength) *. (float_of_int !count)) in
  Printf.printf " %d by %d loop = %g\n%!" x y res_val;
  res_val

let init () =
  srand48 1234;
  shift.(0) <- 1;
  for i = 1 to dim - 1 do
    shift.(i) <- shift.(i - 1) * shape.(i - 1)
  done;
  for iv = 0 to nlinks - 1 do
    set_identity ulinks.(iv) 1.0
  done;
  let x = Array.make dim 0 in
  for iv = 0 to nsites - 1 do
    split x iv;
    parity.(iv) <- 0;
    for i = 0 to dim - 1 do
      parity.(iv) <- parity.(iv) lxor x.(i)
    done;
    parity.(iv) <- parity.(iv) land 1
  done;
  maketable ();
  print_endline "initialization done"

let main () =
  if Array.length Sys.argv > 1 then
    beta := float_of_string Sys.argv.(1);
  init ();
  Printf.printf "lattice size %d" shape.(0);
  for i = 1 to dim - 1 do
    Printf.printf " by %d" shape.(i)
  done;
  Printf.printf "\n vectorlength = %d\n" vectorlength;
  Printf.printf "group=SU(%d)   beta = %6.4f\n" group !beta;
  Printf.printf "-----------------\n%!";

  print_endline "test monte";
  for iter = 0 to 4 do
    let mytime = Sys.time () in
    let count = ref 0 in
    for i = 0 to 4 do
      ignore (monte ulinks);
      incr count
    done;
    renorm ulinks;
    let elapsed = Sys.time () -. mytime in
    let microsec = (1000000.0 /. (float_of_int (!count * nlinks))) *. elapsed in
    Printf.printf "running at %g microseconds per link\n%!" microsec;
    ignore (loop ulinks 2 2)
  done;

  print_endline "test overrelax";
  for iter = 0 to 4 do
    let mytime = Sys.time () in
    let count = ref 0 in
    for i = 0 to 4 do
      ignore (overrelax ulinks);
      incr count
    done;
    renorm ulinks;
    let elapsed = Sys.time () -. mytime in
    let microsec = (1000000.0 /. (float_of_int (!count * nlinks))) *. elapsed in
    Printf.printf "running at %g microseconds per link\n%!" microsec
  done;
  cleanup "all done"

let () = main ()
