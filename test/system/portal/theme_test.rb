require "application_system_test_case"

module Portal
  class ThemeTest < ApplicationSystemTestCase
    test "keeps the theme toggle hidden until the stored preference is applied" do
      visit root_path

      visibility_before_ready = page.evaluate_script(<<~JS)
        (() => {
          const root = document.documentElement;
          root.dataset.themeReady = "false";
          const visibility = getComputedStyle(document.querySelector(".theme-toggle")).visibility;
          root.dataset.themeReady = "true";
          return visibility;
        })()
      JS

      assert_equal "hidden", visibility_before_ready

      page.execute_script("localStorage.setItem('seatwise-theme', 'dark')")
      visit root_path

      assert_selector "html[data-theme='dark'][data-theme-ready='true']"
      assert page.evaluate_script("document.querySelector('input.theme-controller').checked")
      assert_selector ".theme-toggle", visible: true
    end
  end
end
