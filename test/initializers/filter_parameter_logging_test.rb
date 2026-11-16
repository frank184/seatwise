require "test_helper"

class FilterParameterLoggingTest < ActiveSupport::TestCase
  test "OAuth authorization codes are filtered from logged parameters" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal "[FILTERED]", filter.filter(code: "short-lived-authorization-code").fetch(:code)
  end
end
