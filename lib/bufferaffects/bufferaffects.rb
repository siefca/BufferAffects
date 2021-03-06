# = bufferaffects/bufferaffects
# 
# Author::    Paweł Wilk (mailto:pw@gnu.org)
# Copyright:: Copyright (c) 2009 Paweł Wilk
# License::   LGPL
#

# This module is intended to be used as extension
# (class level mixin) for classes using some buffers
# that may be altered by calling certain methods.
#
# It automates resetting of buffers by installing
# wrappers for invasive methods you choose. It rewrites
# selected methods by adding to them code that calls
# buffer(s) flushing method created by you.
#
# === Markers
# 
# To select which methods are invasive for your buffer(s)
# you should use markers which in usage are similar to
# accessors, e.g:
#
#     attr_affects_buffers :domain
#
# Markers may be placed anywhere in the class. Wrapping
# routine will wait for methods to be defined if you
# mark them too early in your code.
#
# ==== Marking methods
#
# To mark methods which should trigger reset operation
# when called use method_affects_buffers which takes
# comma-separated list of symbols describing names
# of these methods.
#
# ==== Marking attributes (setters)
# 
# The marker attr_affects_buffers is similar but it takes
# instance members not methods as arguments. It just installs
# hooks for corresponding setters.
#
# === Buffers flushing method
#
# Default instance method called to reset buffers should be
# defined under name +reset_buffers+
# You may also want to set up your own name by calling
# buffers_reset_method class method.
#
# Buffers flushing method may take none or exactly one argument.
# If your method will take an argument then a name of calling
# method will be passed to it as symbol.
#
# The name of your
# buffers flushing method is passed to subclasses but
# each subclass may redefine it.
#
# Be aware that if you have a class that is subclass of
# a class using BufferAffects then by setting new buffers_reset_method
# you may experience two methods being called. That may happen
# when:
# * your base class has different resetting method assigned
#   than your derivative class
# * you mark some method or attribute again using attr_affects_buffers or method_affects_buffers
# * you will not redefine that method in subclass (despite two facts above)
# That's because we assume that resetting method assigned to a method in superclass
# may be needed there and it shouldn't be taken away.
# 
# === Inherited classes
# 
# This module tries to be inheritance-safe but you will have to
# mark methods and members in subclasses if you are going
# to redefine them. That will install triggers again which is needed
# since redefining creates new code for method which overrides the code
# altered by BufferAffects.
# 
# The smooth way is of course to use +super+
# in overloaded methods so it will also do the job.
#
# To be sure that everything will work fine try to place
# buffers_reset_method clause before any other markers.
#
# === Caution
#
# This code uses method_added hook. If you're going
# to redefine that special method in your class while still using
# this module then remember to call original version or explicitly invoke
# ba_check_method in your version of method_added:
# 
#     ba_check_method(name)
# 
# === Example
#
#    class Main
#     
#      include BufferAffects
#   
#      buffers_reset_method :reset_path_buffer
#      attr_affects_buffers :subpart
#      attr_accessor        :subpart, :otherpart
#
#      def reset_path_buffer(name)
#        @path = nil
#        p "reset called for #{name}"
#      end
#
#      def path
#        @path ||= @subpart.to_s + @otherpart.to_s
#      end
#
#    end
#       
#    obj = Main.new
#    obj.subpart = 'test'
#    p obj.path
#    obj.subpart = '1234'
#    p obj.path

module BufferAffects

  def self.included(base) #:nodoc:
     base.extend(ClassMethods)
  end
  
  module ClassMethods
  
    include AttrInheritable

    attr_inheritable_hash :__ba_wrapped__
    attr_inheritable      :__ba_reset_method__

    # This method sets name of method that will be used to reset buffers.
    
    def buffers_reset_method(name) # :doc:
      name = name.to_s.strip
      raise ArgumentError.new('method name cannot be empty') if name.empty?
      @__ba_reset_method__ = name.to_sym
    end
    private :buffers_reset_method

    # This method sets the marker for hook to be installed.
    # It ignores methods for which wrapper already exists.

    def method_affects_buffers(*names)  # :doc:
      @__ba_methods__ ||= {}
      names.uniq!
      names.collect! { |name| name.to_sym }
      names.delete_if { |name| @__ba_methods__.has_key?(name) }
      ba_methods_wrap(*names)
    end
    private :method_affects_buffers

    # This method searches for setter methods for given
    # member names and tries to wrap them into buffers
    # resetting hooks usting method_affects_buffers
    
    def attr_affects_buffers(*names)  # :doc:
      names.collect! { |name| :"#{name}=" }
      method_affects_buffers(*names)
    end
    private :attr_affects_buffers

    # This method installs hook for given methods or puts their names
    # on the queue if methods haven't been defined yet. The queue is
    # tested each time ba_check_hook is called.
    #  
    # Each processed method can be in one of 2 states:
    #  * false - method is not processed now
    #  * true - method is now processed
    # 
    # After successful wrapping method name (key) and object ID (value) pairs
    # are added two containers: @__ba_wrapped__ and @__ba_methods__
    
    def ba_methods_wrap(*names)
      names.delete_if { |name| @__ba_methods__[name] == true }      # don't handle methods being processed
      kmethods = public_instance_methods +
                private_instance_methods +
                protected_instance_methods
      install_now = names.select { |name| kmethods.include?(name) } # select methods for immediate wrapping
      install_now.delete_if do |name|                               # but don't wrap already wrapped, means:
        self.__ba_wrapped__.has_key?(name) &&                       # - wrapped by our class or other class and
        !@__ba_methods__.has_key?(name) &&                          # - not wrapped by our class
        self.__ba_wrapped__[name] == __ba_reset_method__            # - uses the same resetting method
      end
      
      install_later = names - install_now                           # collect undefined and wrapped methods
      install_later.each { |name| @__ba_methods__[name] = false }   # and add them to the waiting queue
      
      install_now.each { |name| @__ba_methods__[name] = true }      # mark methods as currently processed
      installed = ba_install_hook(*install_now)                     # and install hooks for them
      install_now.each { |name| @__ba_methods__[name] = false }     # mark methods as not processed again
      installed.each_pair do |name,id|                              # and note the reset method assigned to wrapped methods
        @__ba_wrapped__[name] = self.__ba_reset_method__            # inherited container
        @__ba_methods__[name] = self.__ba_reset_method__            # this class's container
      end
    end
    private :ba_methods_wrap

    # This method checks whether method which name is given
    # is now available and should be installed. In most cases you won't
    # need to use it directly.
    
    def ba_check_method(name) # :doc:
      name = name.to_sym
      @__ba_methods__ ||= {}
      if @__ba_methods__.has_key?(name)
        ba_methods_wrap(name)
      end
    end
    private :ba_check_method
    
    # This method installs hook which alters given methods by wrapping
    # them into method that invokes buffers resetting routine. It will
    # not install hook for methods beginning with __ba, which signalizes
    # that they are wrappers for other methods.

    def ba_install_hook(*names)
      @__ba_reset_method__ = 'reset_buffers' if self.__ba_reset_method__.nil?
      installed = {}
      names.uniq.each do |name|
        new_method = name.to_s
        next if new_method[0..3] == '__ba'
        orig_id = instance_method(name.to_sym).object_id
        orig_method = '__ba' + orig_id.to_s + '__'
        reset_method = self.__ba_reset_method__.to_s
        module_eval %{
          alias_method :#{orig_method}, :#{new_method}
          private :#{orig_method}
          def #{new_method}(*args, &block)
            if method(:#{reset_method}).arity == 1
              #{reset_method}(:#{new_method})
            else
              #{reset_method}
            end
            return #{orig_method}(*args, &block)
          end
        }
        installed[name] = orig_id
      end
      return installed
    end
    private :ba_install_hook
    
    # Hook that intercepts added methods. It simply calls ba_check_method
    # passing it a name of added method. In most cases there is no need to call it
    # directly.
    
    def method_added(name)
      ba_check_method(name)
    end
  
  end
    
end

