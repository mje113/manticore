require 'spec_helper'

describe Manticore::Client do
  let(:client) { Manticore::Client.new }

  it "should fetch a URL and return a response" do
    client.get(local_server).should be_a Manticore::Response
  end

  it "should resolve redirections" do
    response = client.get(local_server, headers: {"X-Redirect" => "/foobar"})
    response.code.should == 200
    response.final_url.should == URI(local_server("/foobar"))
  end

  it "should accept custom headers" do
    response = client.get(local_server, headers: {"X-Custom-Header" => "Blaznotts"})
    json = JSON.load(response.body)
    json["headers"]["X-Custom-Header"].should == "Blaznotts"
  end

  it "should enable compression" do
    response = client.get(local_server)
    json = JSON.load(response.body)
    json["headers"].should have_key "Accept-Encoding"
    json["headers"]["Accept-Encoding"].should match("gzip")
  end

  it "should authenticate" do
    client.get(local_server("/auth")).code.should == 401
    client.get(local_server("/auth"), auth: {user: "user", pass: "pass"}).code.should == 200
  end

  it "should proxy" do
    j = JSON.parse(client.get(local_server("/proxy"), proxy: "http://localhost:55442").body)
    j["server_port"].should == 55442
    j["uri"]["port"].should == 55441
  end

  describe "lazy evaluation" do
    it "should not call synchronous requests by default" do
      req = client.get(local_server)
      req.should_not be_called
    end

    context "given a lazy request" do
      subject { client.get(local_server) }

      before do
        subject.should_not be_called
        subject.should_receive(:call).once.and_call_original
      end

      specify { expect { subject.body }.to change      { subject.called? } }
      specify { expect { subject.headers }.to change   { subject.called? } }
      specify { expect { subject.final_url }.to change { subject.called? } }
      specify { expect { subject.code }.to change      { subject.called? } }
      specify { expect { subject.length }.to change    { subject.called? } }
      specify { expect { subject.cookies }.to change   { subject.called? } }
    end

    it "should automatically call synchronous requests that pass a handler block" do
      req = client.get(local_server) {|r| }
      req.should be_called
    end

    it "should not call asynchronous requests even if a block is passed" do
      req = client.async_get(local_server) {|r| }
      req.should_not be_called
    end

    it "should not call asynchronous requests when on_success is passed" do
      req = client.async_get(local_server).on_success {|r| }
      req.should_not be_called
    end

    it "should call async requests on client execution" do
      req = client.async_get(local_server).on_success {|r| }
      expect { client.execute! }.to change { req.called? }.from(false).to(true)
    end
  end

  context "when client-wide cookie management is disabled" do
    let(:client) { Manticore::Client.new cookies: false }

    it "should persist cookies across multiple redirects from a single request" do
      response = client.get(local_server("/cookies/1/2"))
      response.final_url.to_s.should == local_server("/cookies/2/2")
      response.cookies["x"].should be_nil
      response.headers["set-cookie"].should match(/1/)
    end

    it "should not persist cookies between requests" do
      response = client.get(local_server("/cookies/1/2"))
      response.final_url.to_s.should == local_server("/cookies/2/2")
      response.cookies["x"].should be_nil
      response.headers["set-cookie"].should match(/1/)

      response = client.get(local_server("/cookies/1/2"))
      response.final_url.to_s.should == local_server("/cookies/2/2")
      response.cookies["x"].should be_nil
      response.headers["set-cookie"].should match(/1/)
    end
  end

  context "when client-wide cookie management is set to per-request" do
    let(:client) { Manticore::Client.new cookies: :per_request }

    it "should persist cookies across multiple redirects from a single request" do
      response = client.get(local_server("/cookies/1/2"))
      response.final_url.to_s.should == local_server("/cookies/2/2")
      response.headers["set-cookie"].should match(/2/)
      response.cookies["x"].first.value.should == "2"
    end

    it "should not persist cookies between requests" do
      response = client.get(local_server("/cookies/1/2"))
      response.final_url.to_s.should == local_server("/cookies/2/2")
      response.headers["set-cookie"].should match(/2/)
      response.cookies["x"].first.value.should == "2"

      response = client.get(local_server("/cookies/1/2"))
      response.final_url.to_s.should == local_server("/cookies/2/2")
      response.headers["set-cookie"].should match(/2/)
      response.cookies["x"].first.value.should == "2"
    end
  end

  context "when client-wide cookie management is enabled" do
    let(:client) { Manticore::Client.new cookies: true }

    it "should persist cookies across multiple redirects from a single request" do
      response = client.get(local_server("/cookies/1/2"))
      response.final_url.to_s.should == local_server("/cookies/2/2")
      response.cookies["x"].first.value.should == "2"
    end

    it "should persist cookies between requests" do
      response = client.get(local_server("/cookies/1/2"))
      response.final_url.to_s.should == local_server("/cookies/2/2")
      response.cookies["x"].first.value.should == "2"

      response = client.get(local_server("/cookies/1/2"))
      response.final_url.to_s.should == local_server("/cookies/2/2")
      response.cookies["x"].first.value.should == "4"
    end
  end

  context "when compression is disabled" do
    let(:client) {
      Manticore::Client.new do |client, request_config|
        client.disable_content_compression
      end
    }

    it "should disable compression" do
      response = client.get(local_server)
      json = JSON.load(response.body)
      json["headers"]["Accept-Encoding"].should be_nil
    end
  end

  context "when no response charset is specified" do
    let(:content_type) { "text/plain" }

    it "should decode response bodies according to the content-type header" do
      client.get(local_server, headers: {"X-Content-Type" => content_type}).body.encoding.name.should == "ISO-8859-1"
    end
  end

  context "when an invalid response charset is specified" do
    let(:content_type) { "text/plain; charset=bogus" }

    it "should decode the content as UTF-8" do
      client.get(local_server, headers: {"X-Content-Type" => content_type}).body.encoding.name.should == "ISO-8859-1"
    end
  end

  context "when the response charset is UTF-8" do
    let(:content_type) { "text/plain; charset=utf-8" }

    it "should decode response bodies according to the content-type header" do
      client.get(local_server, headers: {"X-Content-Type" => content_type}).body.encoding.name.should == "UTF-8"
    end
  end

  describe "#get" do
    it "should work" do
      response = client.get(local_server)
      JSON.load(response.body)["method"].should == "GET"
    end
  end

  describe "#post" do
    it "should work" do
      response = client.post(local_server)
      JSON.load(response.body)["method"].should == "POST"
    end

    it "should send a body" do
      response = client.post(local_server, body: "This is a post body")
      JSON.load(response.body)["body"].should == "This is a post body"
    end

    it "should send params" do
      response = client.post(local_server, params: {key: "value"})
      JSON.load(response.body)["body"].should == "key=value"
    end
  end

  describe "#put" do
    it "should work" do
      response = client.put(local_server)
      JSON.load(response.body)["method"].should == "PUT"
    end

    it "should send a body" do
      response = client.put(local_server, body: "This is a put body")
      JSON.load(response.body)["body"].should == "This is a put body"
    end

    it "should send params" do
      response = client.put(local_server, params: {key: "value"})
      JSON.load(response.body)["body"].should == "key=value"
    end
  end

  describe "#head" do
    it "should work" do
      response = client.head(local_server)
      JSON.load(response.body).should be_nil
    end
  end

  describe "#options" do
    it "should work" do
      response = client.options(local_server)
      JSON.load(response.body)["method"].should == "OPTIONS"
    end
  end

  describe "#patch" do
    it "should work" do
      response = client.patch(local_server)
      JSON.load(response.body)["method"].should == "PATCH"
    end

    it "should send a body" do
      response = client.patch(local_server, body: "This is a patch body")
      JSON.load(response.body)["body"].should == "This is a patch body"
    end

    it "should send params" do
      response = client.patch(local_server, params: {key: "value"})
      JSON.load(response.body)["body"].should == "key=value"
    end
  end

  describe "async methods" do
    it "should not make a request until execute is called" do
      anchor = Time.now.to_f
      client.async_get("http://localhost:55441/?sleep=0.5")
      (Time.now.to_f - anchor).should < 0.4

      anchor = Time.now.to_f
      client.execute!
      (Time.now.to_f - anchor).should > 0.4
    end

    it "should return the response object, which may then have handlers attached" do
      response = client.async_get("http://localhost:55441/")
      success = false
      response.on_success do
        success = true
      end

      client.execute!
      success.should == true
    end

    it "can chain handlers" do
      client.async_get("http://localhost:55441/").on_success {|r| r.code }
      client.execute!.map(&:callback_result).should == [200]
    end
  end

  describe "#execute!" do
    it "should perform multiple concurrent requests" do
      @times = []
      [55441, 55442].each do |port|
        client.async_get("http://localhost:#{port}/?sleep=1").
          on_success {|response| @times << Time.now.to_f }
      end

      client.execute!
      @times[0].should be_within(0.5).of(@times[1])
    end

    it "should return the results of the handler blocks" do
      [55441, 55442].each do |port|
        client.async_get("http://localhost:#{port}/").
          on_success {|response, request| "Result" }
      end

      client.execute!.map(&:callback_result).should == ["Result", "Result"]
    end
  end

  describe "#clear_pending" do
    it "should remove pending requests" do
      ran = false
      client.async_get("http://google.com").on_success {|r| ran = true }
      client.clear_pending
      client.execute!.should be_empty
      ran.should be_false
    end
  end

  describe "#respond_with" do
    it "should respond with a stubbed response" do
      client.respond_with(body: "body", code: 200).get(local_server).on_success do |response|
        response.should be_a Manticore::StubbedResponse
        response.body.should == "body"
        response.code.should == 200
      end
    end

    context "for synchronous requests" do
      it "should respond only stub the next subsequent response" do
        client.respond_with(body: "body", code: 200)

        client.get(local_server) do |response|
          response.should be_a Manticore::StubbedResponse
        end

        client.get(local_server) do |response|
          response.should be_a Manticore::Response
        end
      end
    end

    context "for synchronous requests" do
      it "should respond only stub the next subsequent response" do
        client.respond_with(body: "body", code: 200)

        client.async_get(local_server).on_success do |response|
          response.should be_a Manticore::StubbedResponse
        end

        client.async_get(local_server).on_success do |response|
          response.should be_a Manticore::Response
        end

        client.execute!
      end
    end
  end

  describe "#stub" do
    it "should respond with a stubbed response until it is unstubbed" do
      client.stub(local_server, body: "body", code: 200)

      called = false
      2.times {
        client.get(local_server) do |response|
          called = true
          response.should be_a Manticore::StubbedResponse
          response.body.should == "body"
          response.code.should == 200
        end
      }

      called.should be_true

      client.clear_stubs!
      client.get(local_server) do |response|
        response.should be_a Manticore::Response
        response.body.should match(/Manticore/)
        response.code.should == 200
      end
    end

    it "stubs only the provided URLs" do
      client.stub local_server, body: "body"
      client.async_get(local_server).on_success {|r| r.should be_a Manticore::StubbedResponse }
      client.async_get(local_server("/other")).on_success {|r| r.should be_a Manticore::Response }
      client.execute!
    end
  end
end