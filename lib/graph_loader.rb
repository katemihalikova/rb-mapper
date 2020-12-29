require_relative '../process_logger'
require 'nokogiri'
require_relative 'graph'
require_relative 'visual_graph'

# Class to load graph from various formats. Actually implemented is Graphviz formats. Future is OSM format.
class GraphLoader
  attr_reader :highway_attributes

  # Create an instance, save +filename+ and preset highway attributes
  def initialize(filename, highway_attributes, dir)
    @filename = filename
    @highway_attributes = highway_attributes
    @dir = dir
  end

  # Load graph from Graphviz file which was previously constructed from this application, i.e. contains necessary data.
  # File needs to contain
  # => 1) For node its 'id', 'pos' (containing its re-computed position on graphviz space) and 'comment' containig string with comma separated lat and lon
  # => 2) Edge (instead of source and target nodes) might contains info about 'speed' and 'one_way'
  # => 3) Generaly, graph contains parametr 'bb' containing array withhou bounds of map as minlon, minlat, maxlon, maxlat
  #
  # @return [+Graph+, +VisualGraph+]
  def load_graph_viz()
    ProcessLogger.log("Loading graph from GraphViz file #{@filename}.")
    gv = GraphViz.parse(@filename)

    # aux data structures
    hash_of_vertices = {}
    list_of_edges = []
    hash_of_visual_vertices = {}
    list_of_visual_edges = []

    # process vertices
    ProcessLogger.log("Processing vertices")
    gv.node_count.times { |node_index|
      node = gv.get_node_at_index(node_index)
      vid = node.id

      v = Vertex.new(vid) unless hash_of_vertices.has_key?(vid)
      ProcessLogger.log("\t Vertex #{vid} loaded")
      hash_of_vertices[vid] = v

      geo_pos = node["comment"].to_s.delete("\"").split(",")
      pos = node["pos"].to_s.delete("\"").split(",")
      hash_of_visual_vertices[vid] = VisualVertex.new(vid, v, geo_pos[0], geo_pos[1], pos[1], pos[0])
      ProcessLogger.log("\t Visual vertex #{vid} in ")
    }

    # process edges
    gv.edge_count.times { |edge_index|
      link = gv.get_edge_at_index(edge_index)
      vid_from = link.node_one.delete("\"")
      vid_to = link.node_two.delete("\"")
      speed = 50
      one_way = false
      link.each_attribute { |k,v|
        speed = v.to_i if k == "speed"
        one_way = true if k == "oneway" && @dir
      }
      e = Edge.new(vid_from, vid_to, speed, one_way)
      list_of_edges << e
      list_of_visual_edges << VisualEdge.new(e, hash_of_visual_vertices[vid_from], hash_of_visual_vertices[vid_to], one_way)
    }

    # Create Graph instance
    g = Graph.new(hash_of_vertices, list_of_edges)

    # Create VisualGraph instance
    bounds = {}
    bounds[:minlon], bounds[:minlat], bounds[:maxlon], bounds[:maxlat] = gv["bb"].to_s.delete("\"").split(",")
    vg = VisualGraph.new(g, hash_of_visual_vertices, list_of_visual_edges, bounds)

    return g, vg
  end

  # Method to load graph from OSM file and create +Graph+ and +VisualGraph+ instances from +self.filename+
  #
  # @return [+Graph+, +VisualGraph+]
  # UC1, UC2
  def load_graph()
    ProcessLogger.log("Loading graph from OSM file #{@filename}.")

    xml = File.open(@filename) { |f| Nokogiri::XML(f) }

    # aux data structures
    hash_of_vertices = {}
    list_of_edges = []
    hash_of_visual_vertices = {}
    list_of_visual_edges = []

    xml.xpath("/osm/way[tag[@k='highway'][#{@highway_attributes.map{|v| "@v='#{v}'"}.join(' or ')}]]").each{|way|

      vertices = way.css("nd").map{|nd|
        vid = nd["ref"]
        if !hash_of_visual_vertices.has_key?(vid)
          node = xml.at_xpath("/osm/node[@id='#{vid}']")
          v = Vertex.new(vid)
          hash_of_vertices[vid] = v
          hash_of_visual_vertices[vid] = VisualVertex.new(vid, v, node["lat"], node["lon"], node["lat"].to_f, node["lon"].to_f)
        end
        hash_of_visual_vertices[vid]
      }
      edges = vertices.drop(1).each_with_index.map{|vertex, i| [vertices[i], vertex]}.map{|(visual_vertex_one, visual_vertex_two)|
        speed_element = way.at_xpath("tag[@k='maxspeed']")
        one_way_element = way.at_xpath("tag[@k='oneway']")
        speed = speed_element ? speed_element["v"].to_i : 50
        one_way = @dir && one_way_element ? one_way_element["v"] == "yes" : false
        e = Edge.new(visual_vertex_one.id, visual_vertex_two.id, speed, one_way)
        list_of_edges << e
        list_of_visual_edges << VisualEdge.new(e, visual_vertex_one, visual_vertex_two, one_way)
      }

    }

    # Create Graph instance
    g = Graph.new(hash_of_vertices, list_of_edges)

    # Create VisualGraph instance
    bounds_element = xml.at_css("bounds")
    bounds = {
      :minlat => bounds_element["minlat"],
      :minlon => bounds_element["minlon"],
      :maxlat => bounds_element["maxlat"],
      :maxlon => bounds_element["maxlon"],
    }
    vg = VisualGraph.new(g, hash_of_visual_vertices, list_of_visual_edges, bounds)

    return g, vg
  end
end
