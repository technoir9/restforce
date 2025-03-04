# frozen_string_literal: true

module Restforce
  class Middleware::RaiseError < Faraday::Middleware
    # Required for Faraday versions pre-v1.2.0 which do not include
    # an implementation of `#call` by default
    def call(env)
      on_request(env) if respond_to?(:on_request)
      @app.call(env).on_complete do |environment|
        on_complete(environment) if respond_to?(:on_complete)
      end
    end

    def on_complete(env)
      @env = env
      case env[:status]
      when 300
        raise Restforce::MatchesMultipleError.new(
          "300: The external ID provided matches more than one record",
          response_values
        )
      when 401
        raise Restforce::UnauthorizedError.new(message, response_values)
      when 404
        raise Restforce::NotFoundError.new(message, response_values)
      when 413
        raise Restforce::EntityTooLargeError.new(
          "413: Request Entity Too Large",
          response_values
        )
      when 400...600
        klass = exception_class_for_error_code(body['errorCode'])
        raise klass.new(message, response_values)
      end
    end

    def message
      message = "#{body['errorCode']}: #{body['message']}"
      message << "\nRESPONSE: #{JSON.dump(@env[:body])}"
    rescue StandardError
      message # if JSON.dump fails, return message without extra detail
    end

    def body
      @body = (@env[:body].is_a?(Array) ? @env[:body].first : @env[:body])

      case @body
      when Hash
        @body
      else
        { 'errorCode' => '(error code missing)', 'message' => @body }
      end
    end

    def response_values
      {
        status: @env[:status],
        headers: @env[:response_headers],
        body: @env[:body]
      }
    end

    ERROR_CODE_MATCHER = /\A[A-Z_]+\z/.freeze

    def exception_class_for_error_code(error_code)
      return Restforce::ResponseError unless ERROR_CODE_MATCHER.match?(error_code)

      Restforce::ErrorCode.get_exception_class(error_code)
    end
  end
end
