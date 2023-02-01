module Websocket = struct
  module Client_connection = Websocketaf.Client_connection
  module Opcode = Websocketaf.Websocket.Opcode
  module Websocket_connection = Websocketaf.Websocket_connection
  module Wsd = Websocketaf.Wsd

  module Testable = struct
    let opcode = Alcotest.testable Opcode.pp_hum (=)
  end

  let parse_frame t serialized_frame =
    let len = String.length serialized_frame in
    let bs =
      Bigstringaf.of_string
        ~off:0
        ~len
        serialized_frame
    in
    Client_connection.read t bs ~off:0 ~len

  (* let serialize_frame ~is_fin frame = *)
    (* let f = Faraday.create 0x100 in *)
    (* Frame.serialize_bytes *)
      (* f *)
      (* ~is_fin *)
      (* ~opcode:`Text *)
      (* ~payload:(Bytes.of_string frame) *)
      (* ~off:0 *)
      (* ~len:(String.length frame); *)
    (* Faraday.serialize_to_string f *)

  let default_error_handler _wsd _exn = assert false

  let test_parsing_ping_frame () =
    let t =
      Client_connection.create ~error_handler:default_error_handler (fun wsd ->
        let frame ~opcode ~is_fin:_ ~len:_ _payload =
          match opcode with
          | `Text
          | `Binary
          | `Continuation
          | `Connection_close
          | `Pong
          | `Other _ -> Alcotest.fail "expected to parse ping frame"
          | `Ping -> Alcotest.(check pass) "ping frame parsed" true true
        in
        let eof () =
          Format.eprintf "EOF\n%!";
          Wsd.close wsd
        in
        { Websocket_connection.frame
        ; eof
        })
    in
    let parsed = parse_frame t "\137\128\000\000\046\216" in
    Alcotest.(check int) "parsed entire frame" 6 parsed;
    (* Alcotest.check Testable.opcode "opcode" `Ping (Frame.opcode frame); *)
    (* Alcotest.(check bool) "has mask" true (Frame.has_mask frame); *)
    (* Alcotest.(check int32) "mask" 11992l (Frame.mask_exn frame); *)
    (* Alcotest.(check int) "payload_length" (Frame.payload_length frame) 0; *)
    (* Alcotest.(check int) "length" (Frame.length frame) 6 *)
  ;;

  let test_parsing_close_frame () =
    let handler_called = ref false in
    let t =
      Client_connection.create ~error_handler:default_error_handler (fun wsd ->
        let frame ~opcode ~is_fin:_ ~len:_ _payload =
          handler_called := true;
          match opcode with
          | `Text
          | `Binary
          | `Continuation
          | `Ping
          | `Pong
          | `Other _ -> Alcotest.fail "expected to parse close frame"
          | `Connection_close -> Alcotest.(check pass) "close frame parsed" true true
        in
        let eof () =
          Format.eprintf "EOF\n%!";
          Wsd.close wsd
        in
        { Websocket_connection.frame
        ; eof
        })
    in
    let parsed = parse_frame t "\136\000" in
    Alcotest.(check int) "parsed entire frame" 2 parsed;
    Alcotest.(check bool) "handler called" true !handler_called
    (* Alcotest.(check int) "payload_length" (Frame.payload_length frame) 0; *)
    (* Alcotest.(check int) "length" (Frame.length frame) 2; *)
    (* Alcotest.(check bool) "is_fin" true (Frame.is_fin frame) *)
  ;;

  let read_payload payload f =
    let rev_payload_chunks = ref [] in
    let rec on_read bs ~off ~len =
      rev_payload_chunks := Bigstringaf.substring bs ~off ~len :: !rev_payload_chunks;
      Websocketaf.Payload.schedule_read payload ~on_eof ~on_read
    and on_eof () = f !rev_payload_chunks
    in
    Websocketaf.Payload.schedule_read payload ~on_eof ~on_read

  let test_parsing_text_frame () =
    let handler_called = ref false in
    let ws_handler payload_result wsd =
      let frame ~opcode ~is_fin ~len payload =
        match opcode with
        | `Text ->
          Alcotest.(check pass) "text frame parsed" true true;
          Alcotest.(check int) "payload length" 11 len;
          Alcotest.(check bool) "is_fin" true is_fin;
          read_payload payload (fun rev_payload_chunks ->
            handler_called := true;
            Alcotest.(check (list string)) "payload" payload_result rev_payload_chunks);
        | `Binary
        | `Continuation
        | `Ping
        | `Pong
        | `Other _
        | `Connection_close -> Alcotest.fail "expected to parse text frame"
      in
      let eof () =
        Format.eprintf "EOF\n%!";
        Wsd.close wsd
      in
      { Websocket_connection.frame
      ; eof
      }
    in
    let t =
      Client_connection.create ~error_handler:default_error_handler (ws_handler ["1234567890\n"])
    in
    let serialized_frame =
      "\129\139\086\057\046\216\103\011\029\236\099\015\025\224\111\009\036"
    in
    let parsed = parse_frame t serialized_frame in
    Alcotest.(check bool) "handler called" true !handler_called;
    Alcotest.(check int) "parsed entire frame" (String.length serialized_frame) parsed;
    Client_connection.shutdown t;
    (* Alcotest.check Testable.opcode "opcode" `Text (Frame.opcode frame); *)
    (* Alcotest.(check bool) "has mask" true (Frame.has_mask frame); *)
    (* Alcotest.(check int32) "mask" 1446588120l (Frame.mask_exn frame); *)
    (* Alcotest.(check int) "payload_length" (Frame.payload_length frame) 11; *)
    (* Alcotest.(check int) "length" (Frame.length frame) 17; *)

    (* Now read the same frame but in chunks, to simulate a smaller buffer
       sizes. *)
    handler_called := false;
    let bs =
      Bigstringaf.of_string
        ~off:0
        ~len:(String.length serialized_frame)
        serialized_frame
    in

    let t =
      Client_connection.create ~error_handler:default_error_handler (ws_handler ["4567890\n"; "123"])
    in
    let first_chunk_parsed = Client_connection.read t bs ~off:0 ~len:9
    in
    Alcotest.(check bool) "handler not yet called" false !handler_called;
    Alcotest.(check int) "parsed entire frame" 9 first_chunk_parsed;
    let next_chunk_parsed = Client_connection.read t bs ~off:9 ~len:8
    in
    Alcotest.(check bool) "handler called" true !handler_called;
    Alcotest.(check int) "parsed entire frame" 8 next_chunk_parsed;

  ;;

  (* let test_parsing_fin_bit () = *)
   (* let frame = parse_frame (serialize_frame ~is_fin:false "hello") in *)
    (* Alcotest.check Testable.opcode "opcode" `Text (Frame.opcode frame); *)
    (* Alcotest.(check bool) "is_fin" false (Frame.is_fin frame); *)
   (* let frame = parse_frame (serialize_frame ~is_fin:true "hello") in *)
    (* Alcotest.check Testable.opcode "opcode" `Text (Frame.opcode frame); *)
    (* Alcotest.(check bool) "is_fin" true (Frame.is_fin frame); *)
    (* let rev_payload_chunks = read_payload frame in *)
    (* Alcotest.(check (list string)) "payload" ["hello"] rev_payload_chunks *)

  (* let test_parsing_multiple_frames () = *)
   (* let open Websocketaf in *)
   (* let frames_parsed = ref 0 in *)
   (* let websocket_handler wsd = *)
     (* let frame ~opcode ~is_fin:_ ~len:_ payload = *)
       (* match opcode with *)
       (* | `Text -> *)
         (* incr frames_parsed; *)
         (* Websocketaf.Payload.schedule_read payload *)
           (* ~on_eof:ignore *)
           (* ~on_read:(fun bs ~off ~len -> *)
           (* Websocketaf.Wsd.schedule wsd bs ~kind:`Text ~off ~len) *)
       (* | `Binary *)
       (* | `Continuation *)
       (* | `Connection_close *)
       (* | `Ping *)
       (* | `Pong *)
       (* | `Other _ -> assert false *)
     (* in *)
     (* let eof () = *)
       (* Format.eprintf "EOF\n%!"; *)
       (* Wsd.close wsd *)
     (* in *)
     (* { Websocket_connection.frame *)
     (* ; eof *)
     (* } *)
   (* in *)
   (* let t = *)
    (* Server_connection.create_websocket *)
     (* ~error_handler:(fun _ -> assert false) *)
     (* websocket_handler *)
   (* in *)
   (* let frame = serialize_frame ~is_fin:false "hello" in *)
   (* let frames = frame ^ frame in *)
   (* let len = String.length frames in *)
   (* let bs = Bigstringaf.of_string ~off:0 ~len frames in *)
   (* let read = Server_connection.read t bs ~off:0 ~len in *)
   (* Alcotest.(check int) "Reads both frames" len read; *)
   (* Alcotest.(check int) "Both frames parsed and handled" 2 !frames_parsed; *)
  (* ;; *)

  let tests =
    [ "parsing ping frame",  `Quick, test_parsing_ping_frame
    ; "parsing close frame", `Quick, test_parsing_close_frame
    ; "parsing text frame",  `Quick, test_parsing_text_frame
    (* ; "parsing fin bit",  `Quick, test_parsing_fin_bit *)
    (* ; "parse 2 frames in a payload", `Quick, test_parsing_multiple_frames *)
    ]
end

let () =
  Alcotest.run "websocketaf unit tests"
    [ "websocket", Websocket.tests
    ]
