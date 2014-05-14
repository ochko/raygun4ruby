# -*- coding: utf-8 -*-
require File.expand_path('../../test_helper.rb', __FILE__)
require 'stringio'

class ClientTest < Raygun::UnitTest

  class TestException < StandardError; end

  def setup
    super
    @client = Raygun::Client.new
    fake_successful_entry
  end

  def test_api_key_required_exception
    Raygun.configuration.api_key = nil

    assert_raises Raygun::ApiKeyRequired do
      second_client = Raygun::Client.new
    end
  end

  def test_track_exception
    response = Raygun.track_exceptions do
      raise TestException.new
    end

    assert response.success?
  end

  def test_error_details
    e = TestException.new("A test message")
    e.set_backtrace(["/some/folder/some_file.rb:123:in `some_method_name'",
                     "/another/path/foo.rb:1234:in `block (3 levels) run'"])

    expected_hash = {
      :className =>"ClientTest::TestException",
      :message =>  e.message,
      :stackTrace =>[
        { :lineNumber =>"123",  :fileName =>"/some/folder/some_file.rb", :methodName =>"some_method_name" },
        { :lineNumber =>"1234", :fileName =>"/another/path/foo.rb",      :methodName =>"block (3 levels) run"}
      ]
    }

    assert_equal expected_hash, @client.send(:error_details, e)
  end

  def test_client_details
    expected_hash = {
      :name =>     Raygun::CLIENT_NAME,
      :version =>  Raygun::VERSION,
      :clientUrl =>Raygun::CLIENT_URL
    }

    assert_equal expected_hash, @client.send(:client_details)
  end


  def test_version
    Raygun.setup do |config|
      config.version = 123
    end

    assert_equal 123, @client.send(:version)
  end

  def test_affected_user
    e             = TestException.new("A test message")
    test_env      = { "raygun.affected_user" => { :identifier => "somepooruser@yourapp.com" } }
    expected_hash = test_env["raygun.affected_user"]

    assert_equal expected_hash, @client.send(:build_payload_hash, e, test_env)[:details][:user]
  end

  def test_hostname
    assert_equal Socket.gethostname, @client.send(:hostname)
  end

  def test_unicode
    e = TestException.new('日本語のメッセージ')

    assert_silent { @client.track_exception(e) }
  end

  def test_bad_encoding
    raw_string = (100..1000).to_a.pack('c*')
    if RUBY_VERSION < '1.9'
      bad_message =  raw_string
      bad_exception = TestException.new(bad_message)
    else
      bad_message = raw_string.force_encoding('utf-8')
      bad_exception = TestException.new(bad_message)
      assert !bad_message.valid_encoding?
    end
    assert_silent { @client.track_exception(bad_exception) }
  end

  def test_full_payload_hash
    Timecop.freeze do
      Raygun.configuration.version = 123
      e = TestException.new("A test message")
      e.set_backtrace(["/some/folder/some_file.rb:123:in `some_method_name'",
                       "/another/path/foo.rb:1234:in `block (3 levels) run'"])

      expected_hash = {
        :occurredOn =>Time.now.utc.iso8601,
        :details =>{
          :machineName =>   Socket.gethostname,
          :version =>       123,
          :client =>{
            :name =>     Raygun::CLIENT_NAME,
            :version =>  Raygun::VERSION,
            :clientUrl =>Raygun::CLIENT_URL
          },
          :error =>{
            :className =>"ClientTest::TestException",
            :message =>  e.message,
            :stackTrace =>[
              { :lineNumber =>"123",  :fileName =>"/some/folder/some_file.rb", :methodName =>"some_method_name" },
              { :lineNumber =>"1234", :fileName =>"/another/path/foo.rb",      :methodName =>"block (3 levels) run"}
            ]
          },
          :userCustomData =>{},
          :request =>       {}
        }
      }

      assert_equal expected_hash, @client.send(:build_payload_hash, e)
    end
  end

  def test_getting_request_information
    sample_env_hash = {
      "SERVER_NAME"=>"localhost",
      "REQUEST_METHOD"=>"GET",
      "REQUEST_PATH"=>"/",
      "PATH_INFO"=>"/",
      "QUERY_STRING"=>"a=b&c=4945438",
      "REQUEST_URI"=>"/?a=b&c=4945438",
      "HTTP_VERSION"=>"HTTP/1.1",
      "HTTP_HOST"=>"localhost:3000",
      "HTTP_CONNECTION"=>"keep-alive",
      "HTTP_CACHE_CONTROL"=>"max-age=0",
      "HTTP_ACCEPT"=>"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "HTTP_USER_AGENT"=>"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/29.0.1547.22 Safari/537.36",
      "HTTP_ACCEPT_ENCODING"=>"gzip,deflate,sdch",
      "HTTP_ACCEPT_LANGUAGE"=>"en-US,en;q=0.8",
      "HTTP_COOKIE"=>"cookieval",
      "GATEWAY_INTERFACE"=>"CGI/1.2",
      "SERVER_PORT"=>"3000",
      "SERVER_PROTOCOL"=>"HTTP/1.1",
      "SCRIPT_NAME"=>"",
      "REMOTE_ADDR"=>"127.0.0.1"
    }

    expected_hash = {
      :hostName =>   "localhost",
      :url =>        "/",
      :httpMethod => "GET",
      :iPAddress =>  "127.0.0.1",
      :queryString =>{ "a" => "b", "c" => "4945438" },
      :form =>       nil,
      :headers =>    { "Version"=>"HTTP/1.1", "Host"=>"localhost:3000", "Connection"=>"keep-alive", "Cache-Control"=>"max-age=0", "Accept"=>"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", "User-Agent"=>"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/29.0.1547.22 Safari/537.36", "Accept-Encoding"=>"gzip,deflate,sdch", "Accept-Language"=>"en-US,en;q=0.8", "Cookie"=>"cookieval" },
      :rawData =>    []
    }

    assert_equal expected_hash, @client.send(:request_information, sample_env_hash)
  end

  def test_getting_request_information_with_nil_env
    assert_equal({}, @client.send(:request_information, nil))
  end

  def test_filtering_parameters
    post_body_env_hash = {
      "SERVER_NAME"=>"localhost",
      "REQUEST_METHOD"=>"POST",
      "REQUEST_PATH"=>"/",
      "PATH_INFO"=>"/",
      "QUERY_STRING"=>"",
      "REQUEST_URI"=>"/",
      "HTTP_VERSION"=>"HTTP/1.1",
      "HTTP_HOST"=>"localhost:3000",
      "HTTP_CONNECTION"=>"keep-alive",
      "HTTP_CACHE_CONTROL"=>"max-age=0",
      "HTTP_ACCEPT"=>"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "HTTP_USER_AGENT"=>"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/29.0.1547.22 Safari/537.36",
      "HTTP_ACCEPT_ENCODING"=>"gzip,deflate,sdch",
      "HTTP_ACCEPT_LANGUAGE"=>"en-US,en;q=0.8",
      "HTTP_COOKIE"=>"cookieval",
      "GATEWAY_INTERFACE"=>"CGI/1.2",
      "SERVER_PORT"=>"3000",
      "SERVER_PROTOCOL"=>"HTTP/1.1",
      "SCRIPT_NAME"=>"",
      "REMOTE_ADDR"=>"127.0.0.1",
      "rack.input"=>StringIO.new("a=b&c=4945438&password=swordfish")
    }

    expected_form_hash = { "a" => "b", "c" => "4945438", "password" => "[FILTERED]" }

    assert_equal expected_form_hash, @client.send(:request_information, post_body_env_hash)[:form]
  end

  def test_filtering_nested_params
    post_body_env_hash = {
      "SERVER_NAME"=>"localhost",
      "REQUEST_METHOD"=>"POST",
      "REQUEST_PATH"=>"/",
      "PATH_INFO"=>"/",
      "QUERY_STRING"=>"",
      "REQUEST_URI"=>"/",
      "HTTP_VERSION"=>"HTTP/1.1",
      "HTTP_HOST"=>"localhost:3000",
      "HTTP_CONNECTION"=>"keep-alive",
      "HTTP_CACHE_CONTROL"=>"max-age=0",
      "HTTP_ACCEPT"=>"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "HTTP_USER_AGENT"=>"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/29.0.1547.22 Safari/537.36",
      "HTTP_ACCEPT_ENCODING"=>"gzip,deflate,sdch",
      "HTTP_ACCEPT_LANGUAGE"=>"en-US,en;q=0.8",
      "HTTP_COOKIE"=>"cookieval",
      "GATEWAY_INTERFACE"=>"CGI/1.2",
      "SERVER_PORT"=>"3000",
      "SERVER_PROTOCOL"=>"HTTP/1.1",
      "SCRIPT_NAME"=>"",
      "REMOTE_ADDR"=>"127.0.0.1",
      "rack.input"=>StringIO.new("a=b&bank%5Bcredit_card%5D%5Bcard_number%5D=my_secret_bank_number&bank%5Bname%5D=something&c=123456&user%5Bpassword%5D=my_fancy_password")
    }

    expected_form_hash = { "a" => "b", "bank" => { "credit_card" => { "card_number" => "[FILTERED]" }, "name" => "something" }, "c" => "123456", "user" => { "password" => "[FILTERED]" } }

    assert_equal expected_form_hash, @client.send(:request_information, post_body_env_hash)[:form]
  end

end
