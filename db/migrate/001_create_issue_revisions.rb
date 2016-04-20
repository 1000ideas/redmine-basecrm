class CreateIssueRevisions < ActiveRecord::Migration
  def change
    create_table :issue_revisions do |t|
      t.integer :issue_id, null: false
      t.integer :revision_id, null: false
      t.text :deal_info
    end
  end
end
