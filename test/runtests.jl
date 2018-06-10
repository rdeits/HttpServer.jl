using HttpCommon
using HttpServer
using Compat.Test
using Compat
import HTTP
import MbedTLS

if VERSION > v"0.7-"
    using Sockets: @ip_str
else
    using Base: @ip_str
end


@testset "HttpServer utility functions:" begin
    @testset "`write` correctly writes data response" begin
        response = Response(200, "Hello World!")
        buf = IOBuffer();
        HttpServer.write(buf, response)
        response_string = String(take!(buf))
        vals = split(response_string, "\r\n")
        grep(a::Array, k::AbstractString) = filter(x -> occursin(Regex(k), x), a)[1]
        @test grep(vals, "HTTP") == "HTTP/1.1 200 OK "
        @test grep(vals, "Server") == "Server: Julia/$VERSION"
        # default to text/html
        @test grep(vals, "Content-Type") == "Content-Type: text/html; charset=utf-8"
        # skip date
        @test grep(vals, "Content-Language") == "Content-Language: en"
        @test grep(vals, "Hello") == "Hello World!"
    end
end

import Requests: get, text, statuscode

@testset "HttpServer runs" begin
    @testset "using HTTP protocol on 0.0.0.0:8000" begin
        http = HttpHandler() do req::Request, res::Response
            res = Response( occursin(r"^/hello/",req.resource) ? string("Hello ", split(req.resource,'/')[3], "!") : 404 )
            setcookie!(res, "sessionkey", "abc", Dict("Path"=>"/test", "Secure"=>""))
        end
        server = Server(http)
        @async run(server, 8000)
        sleep(1.0)

        ret = Requests.get("http://localhost:8000/hello/travis")

        @test text(ret) == "Hello travis!"
        @test statuscode(ret) == 200
        @test haskey(ret.cookies, "sessionkey") == true

        let cookie = ret.cookies["sessionkey"]
            @test cookie.value == "abc"
            @test cookie.attrs["Path"] == "/test"
            @test haskey(cookie.attrs, "Secure") == true
        end

        ret = Requests.get("http://localhost:8000/bad")
        @test text(ret) == ""
        @test statuscode(ret) == 404
        close(server)
    end

    @testset "Rerun test using HTTP protocol on 0.0.0.0:8000 after closing" begin
        http = HttpHandler() do req::Request, res::Response
            res = Response( occursin(r"^/hello/",req.resource) ? string("Hello ", split(req.resource,'/')[3], "!") : 404 )
            setcookie!(res, "sessionkey", "abc", Dict("Path"=>"/test", "Secure"=>""))
        end
        server = Server(http)
        @async run(server, 8000)
        sleep(1.0)

        ret = Requests.get("http://localhost:8000/hello/travis")

        @test text(ret) == "Hello travis!"
        @test statuscode(ret) == 200
        @test haskey(ret.cookies, "sessionkey") == true

        let cookie = ret.cookies["sessionkey"]
            @test cookie.value == "abc"
            @test cookie.attrs["Path"] == "/test"
            @test haskey(cookie.attrs, "Secure") == true
        end

        ret = Requests.get("http://localhost:8000/bad")
        @test text(ret) == ""
        @test statuscode(ret) == 404
        close(server)
    end

    @testset "using HTTP protocol on 127.0.0.1:8001" begin
        http = HttpHandler() do req::Request, res::Response
            Response( occursin(r"^/hello/",req.resource) ? string("Hello ", split(req.resource,'/')[3], "!") : 404 )
        end
        server = Server(http)
        @async run(server, host=ip"127.0.0.1", port=8001)
        sleep(1.0)

        ret = Requests.get("http://127.0.0.1:8001/hello/travis")
        @test text(ret) == "Hello travis!"
        @test statuscode(ret) == 200
        close(server)
    end

    @testset "Rerun test using HTTP protocol on 127.0.0.1:8001 after closing" begin
        http = HttpHandler() do req::Request, res::Response
            Response( occursin(r"^/hello/",req.resource) ? string("Hello ", split(req.resource,'/')[3], "!") : 404 )
        end
        server = Server(http)
        @async run(server, host=ip"127.0.0.1", port=8001)
        sleep(1.0)

        ret = Requests.get("http://127.0.0.1:8001/hello/travis")
        @test text(ret) == "Hello travis!"
        @test statuscode(ret) == 200
        close(server)
    end

    @testset "Testing HTTPS on port 8002" begin
        http = HttpHandler() do req, res
            Response("hello")
        end
        server = Server(http)
        cert = MbedTLS.crt_parse_file(joinpath(dirname(@__FILE__),"cert.pem"))
        key = MbedTLS.parse_keyfile(joinpath(dirname(@__FILE__),"key.pem"))
        @async run(server, port=8002, ssl=(cert, key))
        sleep(1.0)
        client_tls_conf = Requests.TLS_VERIFY
        MbedTLS.ca_chain!(client_tls_conf, cert)
        ret = Requests.get("https://localhost:8002", tls_conf=client_tls_conf)
        @test text(ret) == "hello"
        close(server)
    end

    @testset "Rerun test of HTTPS on port 8002 after closing" begin
        http = HttpHandler() do req, res
            Response("hello")
        end
        server = Server(http)
        cert = MbedTLS.crt_parse_file(joinpath(dirname(@__FILE__),"cert.pem"))
        key = MbedTLS.parse_keyfile(joinpath(dirname(@__FILE__),"key.pem"))
        @async run(server, port=8002, ssl=(cert, key))
        sleep(1.0)
        client_tls_conf = Requests.TLS_VERIFY
        MbedTLS.ca_chain!(client_tls_conf, cert)
        ret = Requests.get("https://localhost:8002", tls_conf=client_tls_conf)
        @test text(ret) == "hello"
        close(server)
    end

    # Issue #111
    @testset "Parse HTTP headers" begin
          http = HttpHandler() do req::Request, res::Response
              Response(req.headers["Content-Type"])
          end
          server = Server(http)
          @async run(server, 8000)
          sleep(1.0)

          ret = Requests.post("http://localhost:8000/", data = "√", headers = Dict("Content-Type" => "text/plain"))
          @test text(ret) == "text/plain"
          close(server)
    end
end
