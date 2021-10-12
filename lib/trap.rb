# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  @sigterm = false
  Signal.trap('TERM') do
    if @sigterm
      @project&.logger&.warn('SIGTERM(2) received, aborting...')
      Signal.trap('TERM') do
        @project&.logger&.warn('SIGTERM(*) received, ignoring...')
      end
      @project&.handle_cancel
      @project&.close
      clean_threads
      exit
    else
      @sigterm = true
      @project&.logger&.warn('SIGTERM(1) received, aborting if another SIGTERM is'\
                          ' received in the span of the next one second')
      Thread.new do
        sleep 1
        @sigterm = false
      end
    end
  end
end
