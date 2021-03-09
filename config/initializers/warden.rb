# encoding: utf-8

#  Copyright (c) 2012-2013, Jungwacht Blauring Schweiz. This file is part of
#  hitobito and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito.

# https://redmine.puzzle.ch/issues/3613
#
# Devise modules (rememberable, trackable) use save to update fields.
# This automatically also updates updated_at field.
#
# We use warden hooks to disable automatic updating of timestamps when
# user logs into and logs out of application.

Warden::Manager.prepend_after_set_user :except => :fetch do |record, warden, options|
  record.define_singleton_method(:record_timestamps, Proc.new { false } )
end

Warden::Manager.prepend_before_logout do |record, warden, options|
  record.define_singleton_method(:record_timestamps, Proc.new { false } )
end

# overriding the devise timeoutable hook. This allows to set a session[:valid_for] duration inside controllers.
# This is otherwise not possible. Original method: https://github.com/heartcombo/devise/blob/master/lib/devise/hooks/timeoutable.rb
Warden::Manager.after_set_user do |record, warden, options|
  scope = options[:scope]
  env   = warden.request.env

  if record && warden.authenticated?(scope)
    last_request_at = warden.session(scope)['last_request_at']

    if last_request_at.is_a? Integer
      last_request_at = Time.at(last_request_at).utc
    elsif last_request_at.is_a? String
      last_request_at = Time.parse(last_request_at)
    end

    proxy = Devise::Hooks::Proxy.new(warden)

    session_valid_for = warden.env['rack.session'][:valid_for]

    valid_for_timedout = session_valid_for.present? && 
      Time.now.utc.to_i - last_request_at.to_i > session_valid_for.to_i

    record_timedout = record.timedout?(last_request_at) &&
      !proxy.remember_me_is_active?(record)

    if !env['devise.skip_timeout'] && (valid_for_timedout || record_timedout)
      Devise.sign_out_all_scopes ? proxy.sign_out : proxy.sign_out(scope)
      throw :warden, scope: scope, message: :timeout
    end

    unless env['devise.skip_trackable']
      warden.session(scope)['last_request_at'] = Time.now.utc.to_i
    end
  end
end
