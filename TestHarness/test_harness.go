package main

import (
	"bytes"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"io"
	"log"
	"net"
)

func main() {
	keyPair, err := tls.LoadX509KeyPair("cert.pem", "key.pem")
	if err != nil {
		panic(err)
	}
	cfg := &tls.Config{
		Certificates: []tls.Certificate{keyPair},
	}

	listener, err := tls.Listen("tcp", "localhost:10248", cfg)
	if err != nil {
		panic(err)
	}

	for conn, err := listener.Accept(); err == nil; conn, err = listener.Accept() {
		go func(conn net.Conn) {

			writtenBytes := bytes.NewBuffer(make([]byte, 0, 81920))
			encoder := base64.NewEncoder(base64.StdEncoding, writtenBytes)
			io.CopyN(encoder, rand.Reader, 2000000)

			reader := bytes.NewReader(writtenBytes.Bytes())

			_, err := io.Copy(conn, reader)
			if err != nil {
				panic(err)
			}


			buff2 := bytes.NewBuffer(make([]byte, 0, writtenBytes.Len()))

			num, err := io.CopyN(buff2, conn, int64(writtenBytes.Len()))
			if err != nil {
				panic(err)
			}


			if bytes.Compare(writtenBytes.Bytes(), buff2.Bytes()) == 0 {
				log.Println("Success!", num)
			} else {
				log.Println("Fail :(!\n\n", writtenBytes.Len(), buff2.Len(), string(writtenBytes.Bytes()), "\n", string(buff2.Bytes()))
			}

		//	conn.Close()
		}(conn)
	}
	if err != nil {
		panic(err)
	}

}
