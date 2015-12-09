require_relative 'stats'

describe Messages do
  let(:messages) { Messages.new(12345, 100, nil) } 
  let(:members) { 3.times{Member.new} }
  let(:response) { }
  
  before do
    HTTParty.stub(:get).and_return(response)
  end

end
