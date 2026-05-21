#use "ocaml_qr_decomposition.ml"

(* Solve Rx = b where R is upper triangular *)
let back_substitute r b =
  let m, n = Matrix.dim r in
  let x = Array.make n 0.0 in
  for i = n - 1 downto 0 do
    let sum = ref 0.0 in
    for j = i + 1 to n - 1 do
      sum := !sum +. Matrix.get r i j *. x.(j)
    done;
    x.(i) <- (b.(i) -. !sum) /. Matrix.get r i i
  done;
  x

let solve_least_squares a b =
  let q, r = qr a in
  let m, n = Matrix.dim a in
  (* Compute c = Q^T * b *)
  let c = Matrix.transform' q b in
  (* Take the first n elements of c *)
  let c1 = Array.init n (fun i -> c.(i)) in
  (* Solve R1 * x = c1 where R1 is the top n*n of R *)
  back_substitute r c1

let least_squares_demo () =
  Printf.printf "--- Least Squares Line Fitting Demo ---\n";
  (* Points: (1, 2), (2, 3.5), (3, 5), (4, 7), (5, 8.5) *)
  (* Fitting y = mx + c *)
  let x_points = [|1.0; 2.0; 3.0; 4.0; 5.0|] in
  let y_points = [|2.0; 3.5; 5.0; 7.0; 8.5|] in
  
  let m_points = Array.length x_points in
  let a = Matrix.init m_points 2 (fun i j ->
    if j = 0 then x_points.(i) else 1.0
  ) in
  
  Printf.printf "Matrix A (Design Matrix):\n";
  Matrix.print Format.std_formatter a;
  Format.print_newline ();
  
  let sol = solve_least_squares a y_points in
  let slope = sol.(0) in
  let intercept = sol.(1) in
  
  Printf.printf "\nLeast Squares Solution:\n";
  Printf.printf "  Slope (m): %7.4f\n" slope;
  Printf.printf "  Intercept (c): %7.4f\n" intercept;
  Printf.printf "\nEquation: y = %7.4f * x + %7.4f\n" slope intercept;
  
  Printf.printf "\nVerification (Predicted vs Actual):\n";
  for i = 0 to m_points - 1 do
    let pred = slope *. x_points.(i) +. intercept in
    Printf.printf "  x=%g: actual=%g, predicted=%7.4f, residual=%7.4f\n" 
      x_points.(i) y_points.(i) pred (y_points.(i) -. pred)
  done

let () = least_squares_demo ()
