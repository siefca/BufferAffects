
module AttrInheritable

  def self.included(base) #:nodoc:
     base.extend(ClassMethods)
  end
  
  module ClassMethods

    def attr_inheritable(*variables)
      variables.each do |v|
        module_eval %{
          def #{v}
            @#{v} = superclass.#{v} if !instance_variable_defined?(:@#{v}) && superclass.respond_to?(:#{v})
            @#{v} ||= nil
            return @#{v}
          end
        }
      end
    end

    def attr_inheritable_hash(*variables)
      variables.each do |v|
        module_eval %{
          def #{v}
            @#{v} = superclass.#{v} if !instance_variable_defined?(:@#{v}) && superclass.respond_to?(:#{v})
            @#{v} ||= {}
            return @#{v}
          end
        }
      end
    end

    def attr_inheritable_array(*variables)
      variables.each do |v|
        module_eval %{
          def #{v}
            @#{v} = superclass.#{v} if !instance_variable_defined?(:@#{v}) && superclass.respond_to?(:#{v})
            if @#{v} ||= []
              return @#{v}
            end
        }
      end
    end

  end

end
