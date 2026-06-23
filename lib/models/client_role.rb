# typed: strict
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Models module
  module Models
    # Client role in an HLK pool (platform configuration).
    class ClientRole < T::Enum
      extend T::Sig

      enums do
        Dut     = new('dut')     # Device Under Test (WHQL)
        Sut     = new('sut')     # System Under Test (SVVP)
        Support = new('support') # Support Client for DUT (WHQL)
        Master  = new('master')  # Master Client (SVVP)
        Stress  = new('stress')  # Stress Client (SVVP)
      end

      sig { returns(String) }
      def to_s
        serialize
      end
    end
  end
end
