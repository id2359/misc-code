(* Object-oriented programming concepts from OCaml Journal *)

open Printf

(* 1. Class Hierarchy and Virtual Methods *)
class virtual polygon = object
  method virtual sides : int
  method virtual area : float
end

class rectangle w h = object
  inherit polygon
  method sides = 4
  method area = w *. h
  method contains(x, y) = 0.0 < x && x < w && 0.0 < y && y < h
end

class triangle w h = object
  inherit polygon
  method sides = 3
  method area = w *. h /. 2.0
  method vertices = [0.0, 0.0; w, 0.0; 0.0, h]
end

(* 2. Parametric Polymorphism in Methods (Generics) *)
class virtual ['a] olist = object
  method virtual iter : ('a -> unit) -> unit
end

class ['a] empty = object
  inherit ['a] olist
  method iter _ = ()
end

class ['a] cons h (t : 'a olist) = object
  inherit ['a] olist
  method iter f =
    f h;
    t#iter f
end

(* 3. Private Data and Functional Object Update *)
class counter start_val = object
  val count = start_val
  method get = count
  method increment = {< count = count + 1 >}
  method reset = {< count = 0 >}
end

let print_polygon_info (p : polygon) =
  printf "Polygon: sides=%d, area=%0.2f\n" p#sides p#area

let main () =
  printf "--- OCaml Objects Demo ---\n";
  
  (* Demonstrate class hierarchy *)
  let r = new rectangle 3. 4. in
  let t = new triangle 5. 6. in
  print_polygon_info (r :> polygon);
  print_polygon_info (t :> polygon);

  (* Demonstrate object-oriented list *)
  printf "\nOO List Iteration:\n";
  let list = new cons 1 (new cons 2 (new cons 3 (new empty))) in
  list#iter (printf "  Item: %d\n");

  (* Demonstrate functional object update *)
  printf "\nCounter with functional update:\n";
  let c1 = new counter 10 in
  let c2 = c1#increment in
  let c3 = c2#increment in
  printf "  c1: %d\n" c1#get;
  printf "  c2 (c1+1): %d\n" c2#get;
  printf "  c3 (c2+1): %d\n" c3#get;
  printf "  c3 reset: %d\n" (c3#reset)#get

let () = if !Sys.interactive then () else main ()
