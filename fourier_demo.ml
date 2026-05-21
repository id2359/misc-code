#use "ocaml_fourier.ml"

let fourier_2d_demo () =
  printf "--- 2D FFT Synthetic Pattern Demo ---\n";
  let n = 16 in
  
  (* Create a 2D grid pattern (checkboard-like) *)
  let zss = Array.make_matrix n n (complex 0.0 0.0) in
  for i = 0 to n - 1 do
    for j = 0 to n - 1 do
      let val_f = if (i + j) mod 2 = 0 then 1.0 else -1.0 in
      zss.(i).(j) <- complex val_f 0.0
    done
  done;

  printf "Original 16x16 Grid Pattern (Top 4x4 shown):\n";
  for i = 0 to 3 do
    for j = 0 to 3 do
      printf "%4.0f " zss.(i).(j).Complex.re
    done;
    print_newline ()
  done;

  (* Perform 2D FFT *)
  fft2d 1.0 zss;

  printf "\n2D FFT Magnitudes (Spectral Power Distribution):\n";
  for i = 0 to n - 1 do
    for j = 0 to n - 1 do
      let mag = Complex.norm zss.(i).(j) in
      if mag > 0.1 then
        printf "%4.1f " mag
      else
        printf "  .  "
    done;
    print_newline ()
  done;

  printf "\nObservation: The spectral peaks reflect the high-frequency periodicity of the checkboard.\n";

  (* Inverse 2D FFT *)
  fft2d (-1.0) zss;

  printf "\nReconstructed Pattern (Top 4x4 shown):\n";
  for i = 0 to 3 do
    for j = 0 to 3 do
      printf "%4.0f " zss.(i).(j).Complex.re
    done;
    print_newline ()
  done;

  printf "\n2D FFT demo completed.\n"

let () = fourier_2d_demo ()
