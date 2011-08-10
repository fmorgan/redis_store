require 'redis'
require 'redis/distributed'

module ActionController
  module Session
    class RedisStore < AbstractStore
      include ErrorHelper

      def initialize( app, options = {} )
        super

        @default_options = {
          :namespace => 'rack:session',
          :db => 0,
          :key_prefix => ""
        }.update( options )
        @urls = ActiveRecord::Base.configurations['redis_sessions']['urls'] || ["redis://127.0.0.1:6379/0"]
        @client = Redis::Distributed.new( @urls, @default_options )
        @marshaled_data = nil
      end
            
      private
      
        def prefixed( sid )
          "#{@default_options[:key_prefix]}#{sid}"
        end
    
        def get_session( env, sid )
          sid ||= generate_sid
          session_data = {}
          
          ret = @client.get( prefixed( sid ) )
          
          unless ret.nil?
            @marshaled_data = ret
            session_data = Marshal.load( @marshaled_data )
          end
            
          [sid, session_data]              
        rescue => e          
          ActionController::Base.logger.error( rescue_msg( e ) )          

          [sid, {}]              
        end

        def set_session( env, sid, session_data )
          marshaled_data = Marshal.dump( session_data )
          
          # only write if the sessions data has changed  
          if marshaled_data != @marshaled_data
            node = @client.node_for( prefixed( sid ) )
      
            node.pipelined do
              node.set( prefixed( sid ), Marshal.dump( session_data ) )
              node.zadd( 'concurrent', Time.now.to_i, prefixed( sid ) )                
            end
          end
      
          true
        rescue => e          
          ActionController::Base.logger.error( rescue_msg( e ) )          
          
          false
        end
    end
  end
end