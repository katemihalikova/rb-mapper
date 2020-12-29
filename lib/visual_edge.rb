require 'haversine'

# Class representing visual representation of edge
class VisualEdge
  # Starting +VisualVertex+ of this visual edge
  attr_reader :v1
  # Target +VisualVertex+ of this visual edge
  attr_reader :v2
  # Corresponding edge in the graph
  attr_reader :edge
  # Boolean value given directness
  attr_reader :directed
  # Boolean value emphasize character - drawn differently on output
  attr_accessor :emphesized
  # is part of path
  attr_accessor :part_of_path
  # geo distance between nodes
  attr_reader :distance
  # time needed to go through edge at max speed
  attr_reader :time

  # create instance of +self+ by simple storing of all parameters
  def initialize(edge, v1, v2, directed = false)
  	@edge = edge
    @v1 = v1
    @v2 = v2
    @directed = directed
    @distance = Haversine.distance(v1.lat.to_f, v1.lon.to_f, v2.lat.to_f, v2.lon.to_f).to_km
    @time = @distance / @edge.max_speed
  end
end
