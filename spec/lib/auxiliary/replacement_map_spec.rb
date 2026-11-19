# frozen_string_literal: true

require_relative '../../../lib/all'

# rubocop:disable Metrics/BlockLength
describe AutoHCK::ReplacementMap do
  it 'replaces each placeholder with its value using replace' do
    map = AutoHCK::ReplacementMap.new('@a@' => 'x', '@b@' => 'y')
    expect(map.replace('pre @a@ mid @b@ post')).to eq('pre x mid y post')
  end

  it 'shell-escapes values in create_cmd' do
    map = AutoHCK::ReplacementMap.new('@path@' => '/tmp/a b')
    expect(map.create_cmd('file=@path@')).to eq("file=#{Shellwords.escape('/tmp/a b')}")
  end

  it 'returns the stored replacement for a key using []' do
    map = AutoHCK::ReplacementMap.new('@k@' => 'v')
    expect(map['@k@']).to eq('v')
  end

  it 'returns a new map from merge without changing the receiver' do
    base = AutoHCK::ReplacementMap.new('@a@' => '1')
    combined = base.merge('@b@' => '2')

    expect(base.replace('@a@@b@')).to eq('1@b@')
    expect(combined.replace('@a@@b@')).to eq('12')
  end

  it 'returns nil for [] when the key is not present' do
    map = AutoHCK::ReplacementMap.new('@x@' => 'y')
    expect(map['@missing@']).to be_nil
  end

  it 'expands placeholders in values merged after earlier keys' do
    map = AutoHCK::ReplacementMap.new(
      AutoHCK::ReplacementMap.new('@root@' => '/tmp'),
      '@file@' => '@root@/name'
    )

    expect(map.replace('@file@')).to eq('/tmp/name')
  end

  it 'yields key-value pairs from each' do
    map = AutoHCK::ReplacementMap.new('@p@' => 'q')
    pairs = map.each.map { |k, v| [k, v] }
    expect(pairs).to eq([['@p@', 'q']])
  end

  it 'coerces the template to a string in replace' do
    map = AutoHCK::ReplacementMap.new('@x@' => 'y')
    expect(map.replace(:'@x@')).to eq('y')
  end

  describe '#replace_strict' do
    it 'returns the substituted value when every placeholder is defined' do
      map = AutoHCK::ReplacementMap.new('@bus@' => 'root5.0', '@drive@' => '01')
      expect(map.replace_strict('bus=@bus@ drive=@drive@')).to eq('bus=root5.0 drive=01')
    end

    it 'substitutes and validates nested Hash and Array values' do
      map = AutoHCK::ReplacementMap.new('@file@' => '/ws/01')
      args = { 'bus' => 'root5.0', 'drive' => { 'file' => { 'filename' => '@file@' } }, 'tags' => ['@file@'] }

      expect(map.replace_strict(args)).to eq(
        'bus' => 'root5.0', 'drive' => { 'file' => { 'filename' => '/ws/01' } }, 'tags' => ['/ws/01']
      )
    end

    it 'raises naming every placeholder that survived substitution' do
      map = AutoHCK::ReplacementMap.new('@bus@' => 'root5.0')
      args = { 'bus' => '@bus@', 'path' => '/machine/@storage_dev_id@_dev' }

      error = begin
        map.replace_strict(args)
        nil
      rescue AutoHCK::AutoHCKError => e
        e
      end
      expect(error).to be_a(AutoHCK::AutoHCKError)
      expect(error.message).to include('unsubstituted placeholder(s)')
      expect(error.message).to include('@storage_dev_id@')
    end

    it 'detects hyphenated placeholder names substitution may define' do
      map = AutoHCK::ReplacementMap.new

      expect { map.replace_strict('@root-port@') }
        .to raise_error(AutoHCK::AutoHCKError, /@root-port@/)
    end

    it 'passes non-String leaf values through without validation errors' do
      map = AutoHCK::ReplacementMap.new('@queue@' => '4')

      expect(map.replace_strict({ 'queue' => '@queue@', 'flag' => true, 'count' => 2 }))
        .to eq({ 'queue' => '4', 'flag' => true, 'count' => 2 })
    end
  end
end
# rubocop:enable Metrics/BlockLength
