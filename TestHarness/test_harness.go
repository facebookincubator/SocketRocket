package main

import (
	"bytes"
	"crypto/rand"
	"crypto/tls"
	"io"
	"io/ioutil"
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

	listener, err := tls.Listen("tcp", ":10248", cfg)
	if err != nil {
		panic(err)
	}

	for conn, err := listener.Accept(); err == nil; conn, err = listener.Accept() {
		go func(conn net.Conn) {
			defer func() {
				if err := recover(); err != nil {
					log.Println("Something failed:", err)
				}
			}()

			ch := make(chan bool, 1)
			maxPending := make(chan bool, 2)

			chunkSize := int64(1024 * 1024)
			buff2 := bytes.NewBuffer(make([]byte, 0, chunkSize))

			randBytes := make([]byte, chunkSize)
			_, err := rand.Read(randBytes)
			if err != nil {
				panic(err)
			}
			randReader := bytes.NewReader(randBytes)

			ch <- true
			go func() {
				defer func() {
					if err := recover(); err != nil {
						log.Println("Something failed:", err)
					}
				}()

				defer func() {
					<-ch
				}()

				for i := 0; ; i++ {

					defer func() {
						if err := recover(); err != nil {
							log.Println("Something failed:", err)
						}
					}()
					_, err := io.CopyN(ioutil.Discard, conn, chunkSize)
					if err != nil {
						panic(err)
					}
					<-maxPending

					log.Println("Chunk read back (", i, ")")
				}

				buff2.Reset()
			}()

			for {
				maxPending <- true
				randReader.Seek(0, 0)
				_, err := io.CopyN(conn, randReader, chunkSize)
				if err != nil {
					panic(err)
				}

			}
			ch <- true
			conn.Close()
		}(conn)
	}
	if err != nil {
		panic(err)
	}

}
