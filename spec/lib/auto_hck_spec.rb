# frozen_string_literal: true

require_relative '../../lib/auto_hck'

describe AutoHCK do
  describe '.exit_code_for' do
    it 'maps a failed session to the dedicated test-failed exit code' do
      expect(described_class.exit_code_for(:failed)).to eq(described_class::EXIT_TEST_FAILED)
    end

    it 'maps framework error and canceled sessions to the error exit code' do
      expect(described_class.exit_code_for(:error)).to eq(described_class::EXIT_ERROR)
      expect(described_class.exit_code_for(:canceled)).to eq(described_class::EXIT_ERROR)
    end

    it 'maps a passed session to success' do
      expect(described_class.exit_code_for(:passed)).to eq(0)
    end

    it 'maps a still-running session (nothing was run) to success' do
      expect(described_class.exit_code_for(:running)).to eq(0)
    end
  end
end
