module ActionController
  class Base
    def rescue_action_with_raygun(exception)
      unless exception_handled_by_rescue_from?(exception)
        Raygun.track_exception(exception, request.env)
      end
      rescue_action_without_raygun exception
    end

    alias_method :rescue_action_without_raygun, :rescue_action
    alias_method :rescue_action, :rescue_action_with_raygun
    protected :rescue_action

    private

    def exception_handled_by_rescue_from?(exception)
      respond_to?(:handler_for_rescue) && handler_for_rescue(exception)
    end
  end
end
