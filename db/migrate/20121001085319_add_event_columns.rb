#  Copyright (c) 2012-2013, Jungwacht Blauring Schweiz. This file is part of
#  hitobito and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito.

class AddEventColumns < ActiveRecord::Migration[4.2]
  def change
    add_column :events, :participant_count, :integer, default: 0
    change_column :events, :type, :string, null: true
  end
end
