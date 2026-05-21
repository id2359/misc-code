(* Fourier Transform implementation from OCaml Journal *)

open Printf

let complex r i = { Complex.re = r; im = i }
let ( +: ) = Complex.add
let ( -: ) = Complex.sub
let ( *: ) = Complex.mul

let pi = 4.0 *. atan 1.0

(* Radix-2 FFT (1D) *)
let rec fft dir zs =
  match zs with
  | [||] | [|_|] -> ()
  | _ ->
      let n = Array.length zs in
      let zs1 = Array.init (n / 2) (fun i -> zs.(2*i)) in
      let zs2 = Array.init (n / 2) (fun i -> zs.(2*i + 1)) in
      fft dir zs1;
      fft dir zs2;
      let s = dir *. 2.0 *. pi in
      for k = 0 to n/2 - 1 do
        let t = s *. float k /. float n in
        let z1 = zs1.(k) and z2 = zs2.(k) *: complex (cos t) (sin t) in
        zs.(k) <- z1 +: z2;
        zs.(k + n/2) <- z1 -: z2
      done

(* Wrapper to handle scaling *)
let fft_full dir n get set =
  let zs = Array.init n get in
  fft dir zs;
  let s = if dir < 0.0 then 1.0 /. float n else 1.0 in
  for i = 0 to n - 1 do
    set i (complex (s *. zs.(i).Complex.re) (s *. zs.(i).Complex.im))
  done

(* 2D FFT *)
let fft2d dir zss =
  let m = Array.length zss and n = Array.length zss.(0) in
  for i = 0 to m - 1 do
    fft_full dir n (fun j -> zss.(i).(j)) (fun j z -> zss.(i).(j) <- z)
  done;
  for j = 0 to n - 1 do
    fft_full dir m (fun i -> zss.(i).(j)) (fun i z -> zss.(i).(j) <- z)
  done

let main () =
  printf "--- 1D FFT Verification ---\n";
  let n = 8 in
  let signal = Array.init n (fun i -> 
    let t = float i /. float n in
    complex (sin (2.0 *. pi *. t)) 0.0
  ) in
  
  printf "Original signal:\n";
  Array.iter (fun z -> printf "  %7.4f " z.Complex.re) signal;
  print_newline ();
  
  let transformed = Array.copy signal in
  fft 1.0 transformed;
  
  printf "Frequencies (Complex):\n";
  Array.iter (fun z -> printf "  (%7.2f, %7.2f) " z.Complex.re z.Complex.im) transformed;
  print_newline ();
  
  let inverse = Array.copy transformed in
  fft_full (-1.0) n (fun i -> inverse.(i)) (fun i z -> inverse.(i) <- z);
  
  printf "Reconstructed signal:\n";
  Array.iter (fun z -> printf "  %7.4f " z.Complex.re) inverse;
  print_newline ();
  
  printf "\nFFT verification completed.\n"

let () = if !Sys.interactive then () else main ()
