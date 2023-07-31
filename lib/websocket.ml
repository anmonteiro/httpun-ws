module IOVec = Httpaf.IOVec

module Opcode = struct
  type standard_non_control =
    [ `Continuation
    | `Text
    | `Binary ]

  type standard_control =
    [ `Connection_close
    | `Ping
    | `Pong ]

  type standard =
    [ standard_non_control
    | standard_control ]

  type t =
    [ standard
    | `Other of int ]

  let code = function
    | `Continuation     -> 0x0
    | `Text             -> 0x1
    | `Binary           -> 0x2
    | `Connection_close -> 0x8
    | `Ping             -> 0x9
    | `Pong             -> 0xa
    | `Other code       -> code

  let code_table : t array =
    [| `Continuation
     ; `Text
     ; `Binary
     ; `Other 0x3
     ; `Other 0x4
     ; `Other 0x5
     ; `Other 0x6
     ; `Other 0x7
     ; `Connection_close
     ; `Ping
     ; `Pong
     ; `Other 0xb
     ; `Other 0xc
     ; `Other 0xd
     ; `Other 0xe
     ; `Other 0xf
     |]

  let unsafe_of_code code =
    Array.unsafe_get code_table code

  let of_code code =
    if code > 0xf
    then None
    else Some (Array.unsafe_get code_table code)

  let of_code_exn code =
    if code > 0xf
    then failwith "Opcode.of_code_exn: value can't fit in four bits";
    Array.unsafe_get code_table code

  let to_int = code
  let of_int = of_code
  let of_int_exn = of_code_exn

  let pp_hum fmt t =
    Format.fprintf fmt "%d" (to_int t)
end

module Close_code = struct
  type standard =
    [ `Normal_closure
    | `Going_away
    | `Protocol_error
    | `Unsupported_data
    | `No_status_rcvd
    | `Abnormal_closure
    | `Invalid_frame_payload_data
    | `Policy_violation
    | `Message_too_big
    | `Mandatory_ext
    | `Internal_server_error
    | `TLS_handshake ]

  type t =
    [ standard | `Other of int ]

  let code = function
    | `Normal_closure             -> 1000
    | `Going_away                 -> 1001
    | `Protocol_error             -> 1002
    | `Unsupported_data           -> 1003
    | `No_status_rcvd             -> 1005
    | `Abnormal_closure           -> 1006
    | `Invalid_frame_payload_data -> 1007
    | `Policy_violation           -> 1008
    | `Message_too_big            -> 1009
    | `Mandatory_ext              -> 1010
    | `Internal_server_error      -> 1011
    | `TLS_handshake              -> 1015
    | `Other code                 -> code

  let code_table : t array =
    [| `Normal_closure
     ; `Going_away
     ; `Protocol_error
     ; `Unsupported_data
     ; `Other 1004
     ; `No_status_rcvd
     ; `Abnormal_closure
     ; `Invalid_frame_payload_data
     ; `Policy_violation
     ; `Message_too_big
     ; `Mandatory_ext
     ; `Internal_server_error
     ; `Other 1012
     ; `Other 1013
     ; `Other 1014
     ; `TLS_handshake
     |]

  let unsafe_of_code code =
    Array.unsafe_get code_table code

  let of_code code =
    if code > 0xffff || code < 1000 then None
    else if code < 1016             then Some (unsafe_of_code (code land 0b1111))
    else Some (`Other code)
  ;;

  let of_code_exn code =
    if code > 0xffff
    then failwith "Close_code.of_code_exn: value can't fit in two bytes";
    if code < 1000
    then failwith "Close_code.of_code_exn: value in invalid range 0-999";
    if code < 1016
    then unsafe_of_code (code land 0b1111)
    else `Other code
  ;;

  let to_int = code
  let of_int = of_code
  let of_int_exn = of_code_exn
end

module Frame = struct
  let apply_mask mask ?(off=0) ~src_off ?len bs =
    let len =
      match len with
      | None -> Bigstringaf.length bs
      | Some n -> n
    in
    for i = off to off + len - 1 do
      let j = (i + src_off - off) mod 4 in
      (* let j = (i - off) mod 4 in *)
      let c = Bigstringaf.unsafe_get bs i |> Char.code in
      let c = c lxor Int32.(logand (shift_right mask (8 * (3 - j))) 0xffl |> to_int) in
      Bigstringaf.unsafe_set bs i (Char.unsafe_chr c)
    done
  ;;

  let apply_mask_bytes mask bs ~src_off ~off ~len =
    for i = off to off + len - 1 do
      (* let j = (i - off) mod 4 in *)
      let j = (i + src_off - off) mod 4 in
      let c = Bytes.unsafe_get bs i |> Char.code in
      let c = c lxor Int32.(logand (shift_right mask (8 * (3 - j))) 0xffl |> to_int) in
      Bytes.unsafe_set bs i (Char.unsafe_chr c)
    done
  ;;
end
