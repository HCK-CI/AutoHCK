# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    def replace_string(str, replacement_list)
      result = str
      replacement_list.each do |k, v|
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

    def replace_string_recursive(str, replacement_list)
      result = replace_string(str, replacement_list)
      return result if result == str

      replace_string_recursive(result, replacement_list)
    end
  end
end
