# @prettier/plugin-ruby calls JSON.fast_generate, removed in the JSON gem used by Ruby 4.
require "json"

module JSON
  def self.fast_generate(object, *args)
    generate(object, *args)
  end
end
