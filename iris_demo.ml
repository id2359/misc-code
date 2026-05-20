#use "ocaml_neural_network.ml"

let iris_data = [|
  (* Setosa *)
  [|5.1; 3.5; 1.4; 0.2|], [|1.0; 0.0; 0.0|];
  [|4.9; 3.0; 1.4; 0.2|], [|1.0; 0.0; 0.0|];
  [|4.7; 3.2; 1.3; 0.2|], [|1.0; 0.0; 0.0|];
  [|4.6; 3.1; 1.5; 0.2|], [|1.0; 0.0; 0.0|];
  [|5.0; 3.6; 1.4; 0.2|], [|1.0; 0.0; 0.0|];
  (* Versicolour *)
  [|7.0; 3.2; 4.7; 1.4|], [|0.0; 1.0; 0.0|];
  [|6.4; 3.2; 4.5; 1.5|], [|0.0; 1.0; 0.0|];
  [|6.9; 3.1; 4.9; 1.5|], [|0.0; 1.0; 0.0|];
  [|5.5; 2.3; 4.0; 1.3|], [|0.0; 1.0; 0.0|];
  [|6.5; 2.8; 4.6; 1.5|], [|0.0; 1.0; 0.0|];
  (* Virginica *)
  [|6.3; 3.3; 6.0; 2.5|], [|0.0; 0.0; 1.0|];
  [|5.8; 2.7; 5.1; 1.9|], [|0.0; 0.0; 1.0|];
  [|7.1; 3.0; 5.9; 2.1|], [|0.0; 0.0; 1.0|];
  [|6.3; 2.9; 5.6; 1.8|], [|0.0; 0.0; 1.0|];
  [|6.5; 3.0; 5.8; 2.2|], [|0.0; 0.0; 1.0|];
|]

(* Simple normalization: divide by max values observed in Iris dataset *)
let normalize (inputs, targets) =
  let norm_inputs = [|
    inputs.(0) /. 8.0;
    inputs.(1) /. 4.5;
    inputs.(2) /. 7.0;
    inputs.(3) /. 2.5
  |] in
  norm_inputs, targets

let normalized_iris = Array.map normalize iris_data

let iris_main () =
  Random.self_init ();
  let ni = 4 in
  let nh = 10 in
  let no = 3 in
  let net = neuralNet ni nh no in
  Printf.printf "Training on Iris dataset...\n%!";
  let trained_net = train net normalized_iris 20000 0.2 0.1 in
  Printf.printf "Testing on training data:\n";
  test normalized_iris trained_net

let () = iris_main ()
