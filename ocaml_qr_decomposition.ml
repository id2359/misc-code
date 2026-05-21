(* QR Decomposition implementation from OCaml Journal *)

module Matrix = struct
  type t = float array array

  let get a i j = a.(i).(j)
  let set a i j x = a.(i).(j) <- x

  let dim a =
    let m = Array.length a in
    if m=0 then 0, 0 else
      m, Array.length a.(0)

  let init m n f =
    Array.init m (fun i -> Array.init n (f i))
      
  let row a i =
    let _, n = dim a in
    Array.init n (fun j -> get a i j)
      
  let col a j =
    let m, _ = dim a in
    Array.init m (fun i -> get a i j)
      
  let dot u v =
    let n = Array.length u in
    let x = ref 0.0 in
    for k=0 to n-1 do
      x := !x +. u.(k) *. v.(k)
    done;
    !x

  let mul a b =
    let am, an = dim a and bm, bn = dim b in
    assert(an = bm);
    let c = Array.init am (fun _ -> Array.make bn 0.0) in
    for i=0 to am-1 do
      for j=0 to bn-1 do
        let x = ref 0.0 in
        for k=0 to an-1 do
          x := !x +. a.(i).(k) *. b.(k).(j)
        done;
        c.(i).(j) <- !x
      done
    done;
    c

  let transform a u =
    let m, n = dim a in
    assert(n = Array.length u);
    let v = Array.make m 0.0 in
    for i=0 to m-1 do
      let x = ref 0.0 in
      for j=0 to n-1 do
        x := !x +. a.(i).(j) *. u.(j)
      done;
      v.(i) <- !x
    done;
    v

  let transform' a u =
    let m, n = dim a in
    assert(m = Array.length u);
    let v = Array.make n 0.0 in
    for i=0 to n-1 do
      let x = ref 0.0 in
      for j=0 to m-1 do
        x := !x +. a.(j).(i) *. u.(j)
      done;
      v.(i) <- !x
    done;
    v

  let transpose a =
    let m, n = dim a in
    let b = Array.init n (fun _ -> Array.make m 0.0) in
    for i=0 to m-1 do
      for j=0 to n-1 do
        b.(j).(i) <- a.(i).(j)
      done
    done;
    b

  let sub_inplace a b_func =
    let m, n = dim a in
    for i=0 to m-1 do
      for j=0 to n-1 do
        a.(i).(j) <- a.(i).(j) -. b_func i j
      done
    done

  let copy a = Array.map Array.copy a

  let print ff a =
    let m, n = dim a in
    Format.fprintf ff "@[";
    for i=0 to m-1 do
      for j=0 to n-1 do
        Format.fprintf ff "%12.5f " (get a i j)
      done;
      Format.fprintf ff "@\n";
    done;
    Format.fprintf ff "@]"
end

let norm a =
  sqrt(Array.fold_left (fun t x -> t +. x *. x) 0.0 a)

let v_vec m n k qa =
  let u = Array.init (m-k) (fun i -> Matrix.get qa (i+k) k) in
  u.(0) <- u.(0) -. norm u;
  let nu = norm u in
  if nu < 1e-15 then Array.make (m-k) 0.0
  else Array.map (fun x -> x /. nu) u

let qr_aux2 m u v k = 
  let m_dim, n_dim = Matrix.dim m in
  for i = 0 to m_dim - 1 do
    for j = 0 to n_dim - 1 do
      if i >= k && j >= k then
        let val_u = u.(i-k) in
        let val_v = v.(j-k) in
        Matrix.set m i j (Matrix.get m i j -. 2.0 *. val_u *. val_v)
    done
  done

let identity m = Matrix.init m m (fun i j -> if i=j then 1.0 else 0.0)

let qr a =
  let m, n = Matrix.dim a in
  let q = identity m in
  let r = identity m in
  let qa = Matrix.copy a in
  for k=0 to n-1 do
    let v = v_vec m n k qa in
    (* Update Q: Q = Q * (I - 2vv^T) *)
    let q_v = Matrix.transform q (Array.init m (fun i -> if i < k then 0.0 else v.(i-k))) in
    Matrix.sub_inplace q (fun i j -> if j < k then 0.0 else 2.0 *. q_v.(i) *. v.(j-k));
    
    (* Update R: R = (I - 2vv^T) * R *)
    let rt_v = Matrix.transform' r (Array.init m (fun i -> if i < k then 0.0 else v.(i-k))) in
    Matrix.sub_inplace r (fun i j -> if i < k then 0.0 else 2.0 *. v.(i-k) *. rt_v.(j));

    (* Update QA for next iteration *)
    let qat_v = Matrix.transform' qa (Array.init m (fun i -> if i < k then 0.0 else v.(i-k))) in
    Matrix.sub_inplace qa (fun i j -> if i < k then 0.0 else 2.0 *. v.(i-k) *. qat_v.(j));
  done;
  q, Matrix.mul r a

let main () =
  let a = Matrix.init 4 3 (fun i j ->
    let data = [|
      [| 2.; -1.;  1.|];
      [| 1.; -5.;  2.|];
      [|-3.;  1.; -4.|];
      [| 1.; -1.;  1.|]
    |] in
    data.(i).(j)
  ) in
  Printf.printf "Original Matrix A:\n";
  Matrix.print Format.std_formatter a;
  Format.print_newline ();
  
  let q, r = qr a in
  Printf.printf "\nMatrix Q:\n";
  Matrix.print Format.std_formatter q;
  Format.print_newline ();
  
  Printf.printf "\nMatrix R:\n";
  Matrix.print Format.std_formatter r;
  Format.print_newline ();
  
  let recon = Matrix.mul q r in
  Printf.printf "\nReconstructed A (Q * R):\n";
  Matrix.print Format.std_formatter recon;
  Format.print_newline ()

let () = if !Sys.interactive then () else main ()
