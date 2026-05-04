# typed: true
# Test-only class; defined at runtime via stub_const in spec/lib/auxiliary/resource_scope_spec.rb.

class ResourceScopeSpecResource < Struct
  sig { params(id: Symbol, log: T::Array[Symbol]).void }
  def initialize(id, log); end

  sig { void }
  def close; end
end
