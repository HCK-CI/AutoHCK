# typed: strict
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Models module
  module Models
    # DriverInstallMethods class
    class DriverInstallMethods < T::Enum
      extend T::Sig

      enums do
        PNP = new('PNP')
        NONPNP = new('NON-PNP')
        Custom = new
        NoDrviver = new('no-drv')
      end

      sig { returns(String) }
      def to_s
        serialize
      end
    end
  end
end
