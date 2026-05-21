#use "ocaml_oo.ml"

(* Structural Typing Demo *)
(* This function works with ANY object that has an 'area' method returning a float *)
let print_area (obj : < area : float; .. >) =
  Printf.printf "The area is: %0.2f\n" obj#area

let structural_typing_demo () =
  Printf.printf "\n--- Structural Typing Demo ---\n";
  
  (* Using our polygon classes *)
  let r = new rectangle 10. 5. in
  let t = new triangle 10. 5. in
  print_area r;
  print_area t;

  (* Using an "ad-hoc" object created on the fly *)
  let circle = object
    method area = 3.14159 *. 2. *. 2.
    method radius = 2.0
  end in
  Printf.printf "Circle (ad-hoc): ";
  print_area circle

(* Generic Container Demo *)
let generic_demo () =
  Printf.printf "\n--- Generic OO List Demo ---\n";
  
  let strings = new cons "OCaml" (new cons "is" (new cons "awesome" (new empty))) in
  Printf.printf "String list: ";
  strings#iter (Printf.printf "%s ");
  Printf.printf "\n";

  let floats = new cons 1.1 (new cons 2.2 (new cons 3.3 (new empty))) in
  Printf.printf "Float list: ";
  floats#iter (Printf.printf "%g ");
  Printf.printf "\n"

let () =
  structural_typing_demo ();
  generic_demo ()
