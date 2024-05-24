Oauth::Application.seed_once(:name,
                             name: 'matrix',
                             redirect_uri: 'http://localhost:8008',
                             uid: 'rIKsxGlAZVq6v4fD5y8a_GhqmhxKj9DrO2tGeEONnak',
                             secret: '81kTciK2f0gmDJ6F2MOJksTj9baaqk-AFuOWf4X_GdI',
                             confidential: true,
                             scopes: 'name')
