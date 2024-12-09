# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Models
    class Session < T::Struct
      extend T::Sig
      extend JsonHelper

      class Test < T::Struct
        const :platform, T.nilable(String)
        const :drivers, T.nilable(String)
        const :driver_path, T.nilable(String)
        const :commit, T.nilable(String)
        const :svvp, T.nilable(T::Boolean)
        const :dump, T.nilable(T::Boolean)
        const :gthb_context_prefix, T.nilable(String)
        const :gthb_context_suffix, T.nilable(String)
        const :playlist, T.nilable(String)
        const :select_test_names, T.nilable(String)
        const :reject_test_names, T.nilable(String)
        const :reject_report_sections, T.nilable(String)
        const :boot_device, T.nilable(String)
        const :allow_test_duplication, T.nilable(T::Boolean)
        const :manual, T.nilable(T::Boolean)
        const :package_with_playlist, T.nilable(T::Boolean)
        const :session, T.nilable(String)
        const :latest_session, T.nilable(T::Boolean)
      end

      class Common < T::Struct
        const :verbose, T.nilable(T::Boolean)
        const :config, T.nilable(String)
        const :client_world_net, T.nilable(T::Boolean)
        const :id, T.nilable(String)
        const :share_on_host_path, T.nilable(String)
      end

      const :test, Test
      const :common, T.nilable(Common)
    end
  end
end
