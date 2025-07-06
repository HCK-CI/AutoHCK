class Test
   def initialize(id, name, description, something)
      @id = id
      @name = name
      @description = description
   end

   def dump()
       print @id.to_s + ': ' + @name + ': ' + @description
   end
end

test = Test.new(1, "PR test", "Testing Gemini review", 1234)
test.dump()

