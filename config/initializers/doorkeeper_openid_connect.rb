# frozen_string_literal: true

#  Copyright (c) 2019-2023, Pfadibewegung Schweiz. This file is part of
#  hitobito and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito.

Doorkeeper::OpenidConnect.configure do
  issuer Settings.oidc.issuer

  # $>openssl genrsa 2048
  #   signing_key <<-EOL
  # -----BEGIN RSA PRIVATE KEY-----
  # ....
  # -----END RSA PRIVATE KEY-----
  # EOL

  signing_key Settings.oidc.signing_key.join.presence

  subject_types_supported [:public]

  resource_owner_from_access_token do |access_token|
    # Example implementation:
    # User.find_by(id: access_token.resource_owner_id)
    Person.find_by(id: access_token.resource_owner_id)
  end

  auth_time_from_resource_owner do |resource_owner|
    # Example implementation:
    # resource_owner.current_sign_in_at
  end

  reauthenticate_resource_owner do |resource_owner, return_to|
    # Example implementation:
    # store_location_for resource_owner, return_to
    # sign_out resource_owner
    # redirect_to new_user_session_url
  end

  subject do |resource_owner, application|
    # Example implementation:
    # resource_owner.id
    resource_owner.id

    # or if you need pairwise subject identifier, implement like below:
    # Digest::SHA256.hexdigest("#{resource_owner.id}#{URI.parse(application.redirect_uri).host}#{'your_secret_salt'}")
  end

  # Protocol to use when generating URIs for the discovery endpoint,
  # for example if you also use HTTPS in development
  # protocol do
  #   :https
  # end

  # Expiration time on or after which the ID Token MUST NOT be accepted for processing. (default 120 seconds).
  # expiration 600

  # Example claims:
  # claims do
  #   normal_claim :_foo_ do |resource_owner|
  #     resource_owner.foo
  #   end

  #   normal_claim :_bar_ do |resource_owner|
  #     resource_owner.bar
  #   end
  # end

  claims do
    claim(:email, scope: :email, response: [:user_info, :id_token]) { |resource_owner| resource_owner.email }
    claim(:first_name, scope: :name) { |resource_owner| resource_owner.first_name }
    claim(:last_name, scope: :name)  { |resource_owner| resource_owner.last_name }
    claim(:nickname, scope: :name)   { |resource_owner| resource_owner.nickname }
    claim(:address, scope: :name)    { |resource_owner| resource_owner.address }
    claim(:zip_code, scope: :name)   { |resource_owner| resource_owner.zip_code }
    claim(:town, scope: :name)       { |resource_owner| resource_owner.town }
    claim(:country, scope: :name)    { |resource_owner| resource_owner.country }

    claim(:roles, scope: :with_roles) do |resource_owner|
      resource_owner.decorate.roles_for_oauth
    end
  end
end

Rails.application.config.after_initialize do
  # Add some of the claims after the wagons have loaded

  (Person::PUBLIC_ATTRS - [:id]).each do |attr|
    key = "with_roles_#{attr}".to_sym
    Doorkeeper::OpenidConnect.configuration.claims[key] =
      Doorkeeper::OpenidConnect::Claims::NormalClaim.new(
        name: attr.to_sym,
        scope: :with_roles,
        response: [:user_info],
        generator: Proc.new do |resource_owner|
          resource_owner.send(attr)
        end
      )
  end

  FeatureGate.if('groups.nextcloud') do
    Doorkeeper::OpenidConnect.configuration.claims[:name] =
      Doorkeeper::OpenidConnect::Claims::NormalClaim.new(
        name: :name,
        scope: :nextcloud,
        response: [:user_info, :id_token],
        generator: Proc.new do |resource_owner|
          resource_owner.to_s
        end
      )

    Doorkeeper::OpenidConnect.configuration.claims[:groups] =
      Doorkeeper::OpenidConnect::Claims::NormalClaim.new(
        name: :groups,
        scope: :nextcloud,
        response: [:user_info, :id_token],
        generator: Proc.new do |resource_owner|
          resource_owner.roles.map(&:nextcloud_group).uniq.compact.map(&:to_h)
        end
      )
  end
end

class Doorkeeper::OpenidConnect::ClaimsBuilder
  # Patch the claims generate method, because doorkeeper does not allow to serve the same claim on
  # two different scopes and also ignores its own NormalClaim#name attribute, so we can't have
  # multiple separate claims with different scopes and the same name either.
  def self.generate(access_token, response)
    resource_owner = Doorkeeper::OpenidConnect.configuration.resource_owner_from_access_token.call(access_token)

    Doorkeeper::OpenidConnect.configuration.claims.to_h.map do |name, claim|
      if access_token.scopes.exists?(claim.scope) && claim.response.include?(response)
        # Only change is on the next line: We use claim.name instead of name as key
        [claim.name, claim.generator.call(resource_owner, access_token.scopes, access_token)]
      end
    end.compact.to_h
  end
end

class Doorkeeper::OpenidConnect::UserInfo
  # Patch the claims JSON encode method for the userinfo endpoint, to disable filtering out
  # empty and nil values.
  def as_json(*_)
    claims #.reject { |_, value| value.nil? || value == '' }
  end
end
