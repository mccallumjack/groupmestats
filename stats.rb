require 'HTTParty'

ACCESS_TOKEN = ENV['GROUPME_ACCESS_TOKEN']
# This is the max amount of messages you want to look back in history. I keep it at 2k for speed
MAX_MESSAGES_FETCHED = 2000

class Stats
  
  attr_reader :messages, :members, :group_id
  attr_accessor :messages_by_members, :likes_by_members, :self_likes

  def initialize(num, group_id)
    @messages_by_members = Hash.new([])
    @likes_by_members = Hash.new(0)
    @self_likes = Hash.new(0)
    @group_id = group_id
    @members = Members.new(group_id).members
    @messages = FetchMessages.new(num, group_id).messages
    user_messages
    user_likes
  end

  def user_messages
    members.each do |member|
      m = messages.select{|message| message["user_id"] == member["user_id"]}
      messages_by_members[member] = m
    end
  end

  def user_likes
    messages.each do |message|
      message["favorited_by"].each do |fav_user_id|
        likes_by_members[fav_user_id] += 1
        self_likes[fav_user_id] += 1 if fav_user_id == message["user_id"]
      end
    end
  end

  def print_member_likes
    puts "Total Likes Given"
    members.each do |member|
      puts "#{member["nickname"]}: #{self.likes_by_members[member["user_id"]]}"
    end
    return nil
  end

  def print_self_likes
    puts "Self Likes Given"
    members.each do |member|
      puts "#{member["nickname"]}: #{self.self_likes[member["user_id"]]}" if self.self_likes[member["user_id"]] > 0
    end
  end

  def print_message_stats
    messages_by_members.each do |member, messages|
      total_likes = messages.reduce(0) do |sum, message|
        sum += message["favorited_by"].count
      end
      puts "Member: #{member["nickname"]}: #{messages.count} messages and #{total_likes} likes for a ratio of #{(total_likes.to_f / messages.count).round(2)} likes per message"
    end
    return nil
  end

  def print_top_25_messages
    puts "Top 25 Messages"
    top_messages = self.messages.sort_by{ |message| message["favorited_by"].count }.reverse
    top_messages[0..24].each_with_index do |message, index|
      print (index + 1).to_s + ") "
      pretty_print(message)
    end
    return nil
  end

  def pretty_print(message)
    name = message["name"] || "" 
    text = message["text"] || ""
    likes = message["favorited_by"].count || 0
    time = Time.at(message["created_at"])

    puts name + "(#{time.month}-#{time.day}-#{time.year}) (#{likes} likes): " + text
  end
  
  def run
    puts
    print_message_stats
    puts
    print_top_25_messages
    puts
    print_member_likes
    puts
    print_self_likes
  end
  
end


class FetchMessages
  
  attr_accessor :messages
  attr_reader :group_id

  RATE_LIMIT = 100

  def initialize(num, group_id)
    @messages = []
    @num = num
    @group_id = group_id
    populate_last_x_messages(num)
  end

  def populate_last_x_messages(num)
    before_id = nil
    while messages.count < num
      begin 
        self.messages += Messages.new(group_id, RATE_LIMIT, before_id).messages
        before_id = messages.last["id"]
      rescue
        break
      end
    end
  end

end

class Messages

  attr_reader :options, :group_id

  def initialize(group_id, limit, before_id = nil)
    @options = { :query => { :limit => limit, :before_id => before_id, :access_token => ACCESS_TOKEN } }
    @group_id = group_id
  end

  def messages
    self.call["response"]["messages"]
  end

  def call
    HTTParty.get(url, options)
  end

  def url
    "https://api.groupme.com/v3/groups/#{group_id}/messages"
  end

end

class Members

  attr_reader :options, :group_id
  
  def initialize(group_id)
    @group_id = group_id
    @options = { :query => { :access_token => ACCESS_TOKEN } }
  end

  def members
    self.call["response"]["members"]
  end

  def call
    HTTParty.get(url, options)
  end  

  def url
    "https://api.groupme.com/v3/groups/#{group_id}"
  end

end

class Groups

  attr_reader :options
  attr_writer :groups

  def initialize
    @options = { :query => { :access_token => ACCESS_TOKEN } }
  end

  def groups
    @groups ||= HTTParty.get(url, options)["response"]
  end

  def url
    "http://api.groupme.com/v3/groups"
  end

  def list_groups
    puts "Please select the number of the group you want to see stats for"
    groups.each_with_index do |group, i|
      puts "#{(i + 1).to_s}. #{group["name"]}"
    end
  end

end

groups = Groups.new
groups.list_groups
group_index = gets.chomp.to_i
group_id = groups.groups[group_index-1]["group_id"]
puts "Loading Stats for Group: #{groups.groups[group_index-1]["name"]} "
stats = Stats.new(MAX_MESSAGES_FETCHED, group_id)
puts "Last #{stats.messages.count} Messages"
stats.run
