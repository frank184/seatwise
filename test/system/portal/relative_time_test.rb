require "application_system_test_case"

module Portal
  class RelativeTimeTest < ApplicationSystemTestCase
    test "formats future and past timestamps and leaves invalid values blank" do
      visit root_path

      relative_times = page.evaluate_async_script(<<~JS)
        import("controllers/portal/view_helpers").then(({ formatRelativeTime }) => {
          const now = Date.now();
          arguments[0]({
            future: formatRelativeTime(new Date(now + 2 * 60 * 60 * 1000).toISOString()),
            past: formatRelativeTime(new Date(now - 2 * 60 * 60 * 1000).toISOString()),
            invalid: formatRelativeTime("not a timestamp"),
            missing: formatRelativeTime(undefined),
          });
        });
      JS

      assert_match(/\Ain /, relative_times.fetch("future"))
      assert_match(%r{ ago\z}, relative_times.fetch("past"))
      assert_equal "", relative_times.fetch("invalid")
      assert_equal "", relative_times.fetch("missing")
    end
  end
end
