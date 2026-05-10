# frozen_string_literal: true

require_relative '../../../lib/all'

ResourceScopeSpecResource = Struct.new(:id, :log) do
  def close
    log << id
  end
end

# rubocop:disable Metrics/BlockLength
describe AutoHCK::ResourceScope do
  describe '.open' do
    it 'yields a new scope using the provided resource array' do
      bucket = []
      described_class.open(bucket) do |scope|
        expect(scope).to be_a(described_class)
        scope << ResourceScopeSpecResource.new(:held, [])
      end
      expect(bucket.size).to eq(1)
    end

    it 'returns the value from the block' do
      result = described_class.open([]) { :from_block }
      expect(result).to eq(:from_block)
    end

    it 'closes resources in reverse order (LIFO)' do
      log = []
      described_class.open([]) do |scope|
        scope << ResourceScopeSpecResource.new(:first, log)
        scope << ResourceScopeSpecResource.new(:second, log)
      end
      expect(log).to eq(%i[second first])
    end

    it 'still closes resources when the block raises' do
      log = []
      expect do
        described_class.open([]) do |scope|
          scope << ResourceScopeSpecResource.new(:only, log)
          raise 'boom'
        end
      end.to raise_error('boom')

      expect(log).to eq([:only])
    end

    it 'closes an inner open before the outer scope finishes' do
      log = []
      described_class.open([]) do |outer|
        outer << ResourceScopeSpecResource.new(:outer, log)
        described_class.open([]) do |inner|
          inner << ResourceScopeSpecResource.new(:inner, log)
        end
        expect(log).to eq([:inner])
      end
      expect(log).to eq(%i[inner outer])
    end
  end

  describe '#<<' do
    it 'returns self for chaining' do
      described_class.open([]) do |scope|
        r = ResourceScopeSpecResource.new(:a, [])
        expect(scope << r).to equal(scope)
      end
    end
  end

  describe '#transaction' do
    it 'returns the inner block value' do
      described_class.open([]) do |scope|
        expect(scope.transaction { :inner_result }).to eq(:inner_result)
      end
    end

    it 'moves inner resources to the parent scope and closes them when the parent closes' do
      log = []
      described_class.open([]) do |parent|
        parent << ResourceScopeSpecResource.new(:outer, log)
        parent.transaction do |inner|
          inner << ResourceScopeSpecResource.new(:inner, log)
          expect(log).to be_empty
          :ok
        end
        expect(log).to be_empty
      end
      expect(log).to eq(%i[inner outer])
    end
  end
end
# rubocop:enable Metrics/BlockLength
