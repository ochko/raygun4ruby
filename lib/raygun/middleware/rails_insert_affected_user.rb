module Raygun
  module Middleware
    # Adapted from the Rollbar approach https://github.com/rollbar/rollbar-gem/blob/master/lib/rollbar/middleware/rails/rollbar_request_store.rb
    class RailsInsertAffectedUser

      def initialize(app)
        @app = app
      end

      def call(env)
        response = @app.call(env)
      rescue Exception => exception
        if (controller = env["action_controller.instance"])
          if identifier = AffectedUser.new(controller).identifier
            env["raygun.affected_user"] = { :identifier => identifier }
          end
        end
        raise exception
      end

    end
  end

  class AffectedUser
    attr_accessor :controller

    def initialize(controller)
      self.controller = controller
    end

    def affected_user
      return nil unless controller.respond_to?(affected_user_method)
      controller.send(Raygun.configuration.affected_user_method)
    end

    def identifier
      return unless user = affected_user
      if (m = Raygun.configuration.affected_user_identifier_methods.detect { |m| user.respond_to?(m) })
        user.send(m)
      else
        user
      end
    end

    def affected_user_method
      Raygun.configuration.affected_user_method
    end
  end
end
