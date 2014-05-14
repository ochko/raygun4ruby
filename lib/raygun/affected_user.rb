module Raygun
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
