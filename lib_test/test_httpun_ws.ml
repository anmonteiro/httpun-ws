module Websocket = struct
  module Client_connection = Httpun_ws.Client_connection
  module Opcode = Httpun_ws.Websocket.Opcode
  module Websocket_connection = Httpun_ws.Websocket_connection
  module Wsd = Httpun_ws.Wsd

  module Testable = struct
    let opcode = Alcotest.testable Opcode.pp_hum ( = )
  end

  module Parser = struct
    open Httpun_ws__

    let parse_frame ~handler serialized_frame =
      let parser =
        let open Angstrom in
        Parse.frame >>= fun frame ->
        let { Parse.payload_length; _ } = frame in
        let payload =
          match payload_length with
          | 0 -> Payload.create_empty ()
          | _ ->
            Payload.create
              (Bigstringaf.create 0x100)
              ~when_ready_to_read:(Optional_thunk.some (fun () -> ()))
        in
        let payload_parser = Parse.payload_parser frame payload in
        handler frame payload;
        payload_parser
      in
      match Angstrom.parse_string ~consume:All parser serialized_frame with
      | Ok frame -> frame
      | Error err -> Alcotest.fail err

    let serialize_frame ~is_fin frame =
      let f = Faraday.create 0x100 in
      Serialize.serialize_bytes
        f
        ~mode:`Server
        ~is_fin
        ~opcode:`Text
        ~payload:(Bytes.of_string frame)
        ~off:0
        ~src_off:0
        ~len:(String.length frame);
      Faraday.serialize_to_string f

    let test_parsing_ping_frame () =
      let parsed = ref false in
      parse_frame "\137\128\000\000\046\216" ~handler:(fun frame _payload ->
        parsed := true;
        Alcotest.check Testable.opcode "opcode" `Ping frame.opcode;
        Alcotest.(check (option int32)) "mask" (Some 11992l) frame.mask;
        Alcotest.(check int) "payload_length" 0 frame.payload_length);
      Alcotest.(check bool) "parsed" true !parsed

    let test_parsing_close_frame () =
      let parsed = ref false in
      parse_frame "\136\000" ~handler:(fun frame _payload ->
        parsed := true;
        Alcotest.check Testable.opcode "opcode" `Connection_close frame.opcode;
        Alcotest.(check int) "payload_length" 0 frame.payload_length;
        Alcotest.(check bool) "is_fin" true frame.is_fin);
      Alcotest.(check bool) "parsed" true !parsed

    let read_payload payload =
      let rev_payload_chunks = ref [] in
      Payload.schedule_read payload ~on_eof:ignore ~on_read:(fun bs ~off ~len ->
        rev_payload_chunks :=
          Bigstringaf.substring bs ~off ~len :: !rev_payload_chunks);
      !rev_payload_chunks

    let test_parsing_text_frame () =
      let parsed = ref false in
      let payload = ref None in
      parse_frame
        "\129\139\086\057\046\216\103\011\029\236\099\015\025\224\111\009\036"
        ~handler:(fun frame pload ->
          parsed := true;
          Alcotest.check Testable.opcode "opcode" `Text frame.opcode;
          Alcotest.(check (option int32)) "mask" (Some 1446588120l) frame.mask;
          Alcotest.(check int) "payload_length" 11 frame.payload_length;
          Alcotest.(check bool) "is_fin" true frame.is_fin;
          payload := Some pload);
      Alcotest.(check bool) "parsed" true !parsed;
      let rev_payload_chunks = read_payload (Option.get !payload) in
      Alcotest.(check (list string))
        "payload"
        [ "1234567890\n" ]
        rev_payload_chunks

    let test_parsing_fin_bit () =
      let parsed = ref false in
      parse_frame
        (serialize_frame ~is_fin:false "hello")
        ~handler:(fun frame _payload ->
          parsed := true;
          Alcotest.check Testable.opcode "opcode" `Text frame.opcode;
          Alcotest.(check bool) "is_fin" false frame.is_fin);
      Alcotest.(check bool) "parsed" true !parsed;
      parsed := false;
      let payload = ref None in
      parse_frame
        (serialize_frame ~is_fin:true "hello")
        ~handler:(fun frame pload ->
          parsed := true;
          Alcotest.check Testable.opcode "opcode" `Text frame.opcode;
          Alcotest.(check bool) "is_fin" true frame.is_fin;
          payload := Some pload);
      Alcotest.(check bool) "parsed" true !parsed;
      let rev_payload_chunks = read_payload (Option.get !payload) in
      Alcotest.(check (list string)) "payload" [ "hello" ] rev_payload_chunks

    let test_parsing_multiple_frames () =
      let frames_parsed = ref 0 in
      let websocket_handler wsd =
        let frame ~opcode ~is_fin:_ ~len:_ payload =
          match opcode with
          | `Text ->
            incr frames_parsed;
            let rec on_read bs ~off ~len =
              Wsd.schedule wsd ~kind:`Text bs ~off ~len;
              Payload.schedule_read payload ~on_eof:ignore ~on_read
            in
            Payload.schedule_read payload ~on_eof:ignore ~on_read
          | `Binary | `Continuation | `Connection_close | `Ping | `Pong
          | `Other _ ->
            assert false
        in
        let eof ?error () =
          match error with
          | Some _ -> assert false
          | None ->
            Format.eprintf "EOF\n%!";
            Wsd.close wsd
        in
        { Websocket_connection.frame; eof }
      in
      let t = Server_connection.create_websocket websocket_handler in
      let frame = serialize_frame ~is_fin:false "hello" in
      let frames = frame ^ frame in
      let len = String.length frames in
      let bs = Bigstringaf.of_string ~off:0 ~len frames in
      let read = Server_connection.read t bs ~off:0 ~len in
      ignore @@ Server_connection.next_read_operation t;
      Alcotest.(check int) "Reads both frames" len read;
      Alcotest.(check int) "Both frames parsed and handled" 2 !frames_parsed

    let tests =
      [ "parsing ping frame", `Quick, test_parsing_ping_frame
      ; "parsing close frame", `Quick, test_parsing_close_frame
      ; "parsing text frame", `Quick, test_parsing_text_frame
      ; "parsing fin bit", `Quick, test_parsing_fin_bit
      ; "parse 2 frames in a payload", `Quick, test_parsing_multiple_frames
      ]
  end

  let read_frame t serialized_frame =
    let len = String.length serialized_frame in
    let bs = Bigstringaf.of_string ~off:0 ~len serialized_frame in
    Client_connection.read t bs ~off:0 ~len

  let test_reading_ping_frame () =
    let t =
      Client_connection.create (fun wsd ->
        let frame ~opcode ~is_fin:_ ~len:_ _payload =
          match opcode with
          | `Text | `Binary | `Continuation | `Connection_close | `Pong
          | `Other _ ->
            Alcotest.fail "expected to parse ping frame"
          | `Ping -> Alcotest.(check pass) "ping frame parsed" true true
        in
        let eof ?error () =
          match error with
          | Some _ -> assert false
          | None ->
            Format.eprintf "EOF\n%!";
            Wsd.close wsd
        in
        { Websocket_connection.frame; eof })
    in
    let parsed = read_frame t "\137\128\000\000\046\216" in
    Alcotest.(check int) "parsed entire frame" 6 parsed

  let test_reading_close_frame () =
    let handler_called = ref false in
    let t =
      Client_connection.create (fun wsd ->
        let frame ~opcode ~is_fin:_ ~len:_ _payload =
          handler_called := true;
          match opcode with
          | `Text | `Binary | `Continuation | `Ping | `Pong | `Other _ ->
            Alcotest.fail "expected to parse close frame"
          | `Connection_close ->
            Alcotest.(check pass) "close frame parsed" true true
        in
        let eof ?error () =
          match error with
          | Some _ -> assert false
          | None ->
            Format.eprintf "EOF\n%!";
            Wsd.close wsd
        in
        { Websocket_connection.frame; eof })
    in
    let parsed = read_frame t "\136\000" in
    Alcotest.(check int) "parsed entire frame" 2 parsed;
    Alcotest.(check bool) "handler called" true !handler_called

  let read_payload payload f =
    let rev_payload_chunks = ref [] in
    let rec on_read bs ~off ~len =
      rev_payload_chunks :=
        Bigstringaf.substring bs ~off ~len :: !rev_payload_chunks;
      Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
    and on_eof () = f !rev_payload_chunks in
    Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read

  let test_reading_text_frame () =
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
            Alcotest.(check (list string))
              "payload"
              payload_result
              rev_payload_chunks)
        | `Binary | `Continuation | `Ping | `Pong | `Other _ | `Connection_close
          ->
          Alcotest.fail "expected to parse text frame"
      in
      let eof ?error () =
        match error with
        | Some _ -> assert false
        | None ->
          Format.eprintf "EOF\n%!";
          Wsd.close wsd
      in
      { Websocket_connection.frame; eof }
    in
    let t = Client_connection.create (ws_handler [ "1234567890\n" ]) in
    let serialized_frame =
      "\129\139\086\057\046\216\103\011\029\236\099\015\025\224\111\009\036"
    in
    let parsed = read_frame t serialized_frame in
    Alcotest.(check bool) "handler called" true !handler_called;
    Alcotest.(check int)
      "parsed entire frame"
      (String.length serialized_frame)
      parsed;
    Client_connection.shutdown t;

    (* Now read the same frame but in chunks, to simulate a smaller buffer
       sizes. *)
    handler_called := false;
    let bs =
      Bigstringaf.of_string
        ~off:0
        ~len:(String.length serialized_frame)
        serialized_frame
    in

    let t = Client_connection.create (ws_handler [ "4567890\n"; "123" ]) in
    let first_chunk_parsed = Client_connection.read t bs ~off:0 ~len:9 in
    Alcotest.(check bool) "handler not yet called" false !handler_called;
    Alcotest.(check int) "parsed entire frame" 9 first_chunk_parsed;
    let next_chunk_parsed = Client_connection.read t bs ~off:9 ~len:8 in
    Alcotest.(check bool) "handler called" true !handler_called;
    Alcotest.(check int) "parsed entire frame" 8 next_chunk_parsed

  let tests =
    [ "reading ping frame", `Quick, test_reading_ping_frame
    ; "reading close frame", `Quick, test_reading_close_frame
    ; "reading text frame", `Quick, test_reading_text_frame
    ]
end

let () =
  Alcotest.run
    "httpun-ws unit tests"
    [ "websocket frame parsing", Websocket.Parser.tests
    ; "reading", Websocket.tests
    ]
