# typed: true

# frozen_string_literal: true

module AutoHCK
  class MultiLogger
    extend T::Sig

    sig { params(message: T.nilable(String)).void }
    def fatal(message = nil); end

    sig { params(message: T.nilable(String)).void }
    def error(message = nil); end

    sig { params(message: T.nilable(String)).void }
    def warn(message = nil); end

    sig { params(message: T.nilable(String)).void }
    def info(message = nil); end

    sig { params(message: T.nilable(String)).void }
    def debug(message = nil); end

    sig { params(message: T.nilable(String)).void }
    def unknown(message = nil); end
  end
end
