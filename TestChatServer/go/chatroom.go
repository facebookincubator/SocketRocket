//
// Copyright 2012 Square Inc.
// Portions Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
// 
// This source code is licensed under the license found in the
// LICENSE-examples file in the root directory of this source tree.
//

package main

import (
	"code.google.com/p/go.net/websocket"
	"net/http"
)

// Msg stores both the message and the connection
type Msg struct {
	sender *websocket.Conn
	msg    string
}

func run(reg chan *websocket.Conn, unreg chan *websocket.Conn, msg chan Msg) {
	conns := make(map[*websocket.Conn]int)
	for {
		select {
		case c := <-reg:
			conns[c] = 1
		case c := <-unreg:
			delete(conns, c)
		case msg := <-msg:
			for c := range conns {
				if c != msg.sender {
					websocket.Message.Send(c, msg.msg)
				}
			}
		}
	}
}

func newChatServer(reg chan *websocket.Conn, unreg chan *websocket.Conn, msg chan Msg) websocket.Handler {
	return func(ws *websocket.Conn) {
		reg <- ws
		for {
			var message string
			err := websocket.Message.Receive(ws, &message)
			if err != nil {
				unreg <- ws
				break
			}
			msg <- Msg{ws, message}
		}
	}
}

func main() {
	reg := make(chan *websocket.Conn)
	unreg := make(chan *websocket.Conn)
	msg := make(chan Msg)

	http.Handle("/chat", websocket.Handler(newChatServer(reg, unreg, msg)))
	http.Handle("/", http.FileServer(http.Dir("../static")))

	go run(reg, unreg, msg)

	err := http.ListenAndServe(":9000", nil)
	if err != nil {
		panic("ListenAndServe: " + err.Error())
	}
}
