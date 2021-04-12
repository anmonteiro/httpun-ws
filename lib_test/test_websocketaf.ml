module Websocket = struct
  open Websocketaf.Websocket

  module Testable = struct
    let opcode = Alcotest.testable Opcode.pp_hum (=)
  end

  let parse_frame serialized_frame =
    let parser =
      let open Angstrom in
      (Frame.parse ~buf:Bigstringaf.empty) >>= fun frame ->
        lift (fun () -> frame) (Frame.payload_parser frame)
    in
    match Angstrom.parse_string ~consume:All parser serialized_frame with
    | Ok frame -> frame
    | Error err -> Alcotest.fail err

  let serialize_frame ~is_fin frame =
    let f = Faraday.create 0x100 in
    Frame.serialize_bytes
      f
      ~is_fin
      ~opcode:`Text
      ~payload:(Bytes.of_string frame)
      ~off:0
      ~len:(String.length frame);
    Faraday.serialize_to_string f

  let test_parsing_ping_frame () =
    let frame = parse_frame "\137\128\000\000\046\216" in
    Alcotest.check Testable.opcode "opcode" `Ping (Frame.opcode frame);
    Alcotest.(check bool) "has mask" true (Frame.has_mask frame);
    Alcotest.(check int32) "mask" 11992l (Frame.mask_exn frame);
    Alcotest.(check int) "payload_length" (Frame.payload_length frame) 0;
    Alcotest.(check int) "length" (Frame.length frame) 6

  let test_parsing_close_frame () =
    let frame = parse_frame "\136\000" in
    Alcotest.check Testable.opcode "opcode" `Connection_close (Frame.opcode frame);
    Alcotest.(check int) "payload_length" (Frame.payload_length frame) 0;
    Alcotest.(check int) "length" (Frame.length frame) 2;
    Alcotest.(check bool) "is_fin" true (Frame.is_fin frame)

  let read_payload frame =
    let rev_payload_chunks = ref [] in
    let payload = Frame.payload frame in
    Websocketaf.Payload.schedule_read payload
      ~on_eof:ignore
      ~on_read:(fun bs ~off ~len ->
      rev_payload_chunks := Bigstringaf.substring bs ~off ~len :: !rev_payload_chunks
    );
    !rev_payload_chunks

  let test_parsing_text_frame () =
    let frame = parse_frame "\129\139\086\057\046\216\103\011\029\236\099\015\025\224\111\009\036" in
    Alcotest.check Testable.opcode "opcode" `Text (Frame.opcode frame);
    Alcotest.(check bool) "has mask" true (Frame.has_mask frame);
    Alcotest.(check int32) "mask" 1446588120l (Frame.mask_exn frame);
    Alcotest.(check int) "payload_length" (Frame.payload_length frame) 11;
    Alcotest.(check int) "length" (Frame.length frame) 17;
    let rev_payload_chunks = read_payload frame in
    Alcotest.(check bool) "is_fin" true (Frame.is_fin frame);
    Alcotest.(check (list string)) "payload" ["1234567890\n"] rev_payload_chunks

  let test_parsing_fin_bit () =
   let frame = parse_frame (serialize_frame ~is_fin:false "hello") in
    Alcotest.check Testable.opcode "opcode" `Text (Frame.opcode frame);
    Alcotest.(check bool) "is_fin" false (Frame.is_fin frame);
   let frame = parse_frame (serialize_frame ~is_fin:true "hello") in
    Alcotest.check Testable.opcode "opcode" `Text (Frame.opcode frame);
    Alcotest.(check bool) "is_fin" true (Frame.is_fin frame);
    let rev_payload_chunks = read_payload frame in
    Alcotest.(check (list string)) "payload" ["hello"] rev_payload_chunks

  let test_parsing_multiple_frames () =
   let open Websocketaf in
   let frames_parsed = ref 0 in
   let websocket_handler wsd =
     let frame ~opcode ~is_fin:_ ~len:_ payload =
       match opcode with
       | `Text ->
         incr frames_parsed;
         Websocketaf.Payload.schedule_read payload
           ~on_eof:ignore
           ~on_read:(fun bs ~off ~len ->
           Websocketaf.Wsd.schedule wsd bs ~kind:`Text ~off ~len)
       | `Binary
       | `Continuation
       | `Connection_close
       | `Ping
       | `Pong
       | `Other _ -> assert false
     in
     let eof () =
       Format.eprintf "EOF\n%!";
       Wsd.close wsd
     in
     { Server_connection.frame
     ; eof
     }
   in
   let t =
    Server_connection.create_websocket
     ~error_handler:(fun _ -> assert false)
     websocket_handler
   in
   let frame = serialize_frame ~is_fin:false "hello" in
   let frames = frame ^ frame in
   let len = String.length frames in
   let bs = Bigstringaf.of_string ~off:0 ~len frames in
   let read = Server_connection.read t bs ~off:0 ~len in
   Alcotest.(check int) "Reads both frames" len read;
   Alcotest.(check int) "Both frames parsed and handled" 2 !frames_parsed;
  ;;

  let tests =
    [ "parsing ping frame",  `Quick, test_parsing_ping_frame
    ; "parsing close frame", `Quick, test_parsing_close_frame
    ; "parsing text frame",  `Quick, test_parsing_text_frame
    ; "parsing fin bit",  `Quick, test_parsing_fin_bit
    ; "parse 2 frames in a payload", `Quick, test_parsing_multiple_frames
    ]
end

let () =
  Alcotest.run "websocketaf unit tests"
    [ "websocket", Websocket.tests
    ]
