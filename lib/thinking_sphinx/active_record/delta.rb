module ThinkingSphinx
  module ActiveRecord
    # This module contains all the delta-related code for models. There isn't
    # really anything you need to call manually in here - except perhaps
    # index_delta, but not sure what reason why.
    # 
    module Delta
      # Code for after_commit callback is written by Eli Miller:
      # http://elimiller.blogspot.com/2007/06/proper-cache-expiry-with-aftercommit.html
      # with slight modification from Joost Hietbrink.
      #
      def self.included(base)
        base.class_eval do
          class << self
            # Build the delta index for the related model. This won't be called
            # if running in the test environment.
            #
            def index_delta(instance = nil)
              delta_objects.each { |obj| obj.index(self, instance) }
            end
            
            def delta_objects
              self.sphinx_indexes.collect(&:delta_object).compact
            end
            
            # Temporarily disable delta indexing inside a block, then perform a
            # single rebuild of index at the end.
            #
            # Useful when performing updates to batches of models to prevent
            # the delta index being rebuilt after each individual update.
            #
            # In the following example, the delta index will only be rebuilt
            # once, not 10 times.
            #
            #   SomeModel.suspended_delta do
            #     10.times do
            #       SomeModel.create( ... )
            #     end
            #   end
            #
            def suspended_delta(reindex_after = true, &block)
              define_indexes
              original_setting = ThinkingSphinx.deltas_suspended?
              ThinkingSphinx.deltas_suspended = true
              begin
                yield
              ensure
                ThinkingSphinx.deltas_suspended = original_setting
                self.index_delta if reindex_after
              end
            end
          end
          
          def toggled_delta?
            self.class.delta_objects.any? { |obj| obj.toggled(self) }
          end
          
          private
          
          # Set the delta value for the model to be true.
          def toggle_delta
            self.class.delta_objects.each { |obj|
              obj.toggle(self)
            } if should_toggle_delta?
          end
          
          # Build the delta index for the related model. This won't be called
          # if running in the test environment.
          # 
          def index_delta
            self.class.index_delta(self) if self.class.delta_objects.any? { |obj|
              obj.toggled(self)
            }
          end
          
          def should_toggle_delta?
            self.new_record? || indexed_data_changed?
          end
          
          def indexed_data_changed?
            sphinx_indexes.any? { |index|
              index.fields.any? { |field| field.changed?(self) } ||
              index.attributes.any? { |attrib|
                attrib.public? && attrib.changed?(self) && !attrib.updatable?
              }
            }
          end
        end
      end
    end
  end
end
