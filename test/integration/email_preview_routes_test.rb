require "test_helper"

class EmailPreviewRoutesTest < ActionDispatch::IntegrationTest
  test "letter opener preview route is not available outside development" do
    get "/letter_opener"

    assert_response :not_found
  end
end
