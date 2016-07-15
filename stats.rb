require 'HTTParty'

ACCESS_TOKEN = ENV['GROUPME_ACCESS_TOKEN']
# This is the max amount of messages you want to look back in history. I keep it at 2k for speed
MAX_MESSAGES_FETCHED = 5000

class Stats
  
  attr_reader :messages, :members, :group_id
  attr_accessor :messages_by_members, :likes_by_members, :self_likes, :likes_by_member_per_member

  def initialize(num, group_id)
    @messages_by_members = Hash.new([])
    @likes_by_members = Hash.new(0)
    @likes_by_member_per_member = Hash.new({})
    @self_likes = Hash.new(0)
    @group_id = group_id
    @members = Members.new(group_id).members
    @messages = FetchMessages.new(num, group_id).messages
    user_messages
    user_likes
  end

  def user_messages
    @user_messages ||= 
      members.each do |member|
        m = messages.select{|message| message["user_id"] == member["user_id"]}
        messages_by_members[member] = m
      end
  end

  def user_likes
    @user_likes ||= 
      messages.each do |message|
        message["favorited_by"].each do |fav_user_id|
          likes_by_members[fav_user_id] += 1
          self_likes[fav_user_id] += 1 if fav_user_id == message["user_id"]
          likes_by_member_per_member[fav_user_id] = Hash.new(0) unless likes_by_member_per_member.keys.include?(fav_user_id)
          likes_by_member_per_member[fav_user_id][message["user_id"]] += 1
        end
      end
  end

  def average_likes_per_member_per_person
    averages = {}
    @likes_by_member_per_member.each do |user_id, like_hash|
      averages[user_id] = {}
      like_hash.each do |liked_user_id, num_likes|
        if num_likes.nil? || num_likes == 0 || !user_messages_by_user_id.keys.include?(liked_user_id)
          next
        else
          averages[user_id][liked_user_id] = (num_likes.to_f / user_messages_by_user_id[liked_user_id] * 100).round(2)
        end
      end
    end
    averages
  end

  def user_messages_by_user_id
    @user_messages_by_user_id ||= messages_by_members.map { |k, v| [k["user_id"], v.count] }.to_h
  end

  def get_name_by_user_id(user_id)
    members.select{|member| member["user_id"] == user_id}.first["nickname"]
  end

  def print_average_likes_per_member_per_person
    puts "Average Likes Per Member Per Person - Who are you the toughest critic of?"
    puts "(Number of times you like it vs number of posts)"

    members.each do |member|
      puts
      member_name = member["nickname"]
      puts "For #{member_name}: "
      puts "TOTAL AVERAGE: #{(likes_by_members[member["user_id"]] / (messages.count - messages_by_members[member].count).to_f * 100).round(2)}% of posts"
      puts
      next unless average_likes_per_member_per_person[member["user_id"]]
      average_likes_per_member_per_person[member["user_id"]].each do |liked_member, average|
        print "-- "
        puts "#{get_name_by_user_id(liked_member)} - Liked #{average}%"
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
    puts
    print_average_likes_per_member_per_person
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
