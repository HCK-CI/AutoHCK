# frozen_string_literal: true

module AutoHCK
  module Functest
    extend AutoloadExtension

    autoload_relative :Suite, 'suite'
    autoload_relative :TestCase, 'test_case'
  end
end
