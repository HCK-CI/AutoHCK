# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  class ReplacementMap
    def initialize(...)
      @hash = {}
      merge!(...)
    end

    def each(...)
      @hash.each(...)
    end

    def merge(...)
      self.class.new(self, ...)
    end

    def merge!(*args)
      args.each { |arg| arg&.each { |k, v| @hash[k] = replace(v) } }
    end

    def replace(str)
      result = str.to_s
      @hash.each do |k, v|
        # If replacement is a String it will be substituted for the matched text.
        # It may contain back-references to the pattern's capture groups of the form \d,
        # where d is a group number, or \k<n>, where n is a group name.
        # In the block form, the current match string is passed in as a parameter,
        # and variables such as $1, $2, $`, $&, and $' will be set appropriately.
        # The value returned by the block will be substituted for the match on each call.
        result = result.gsub(k) { v }
      end
      result
    end
  end
end
