require_relative 'lib/graph_loader';
require_relative 'process_logger';

# Class representing simple navigation based on OpenStreetMap project
class OSMSimpleNav

  # Creates an instance of navigation. No input file is specified in this moment.
  def initialize
    # register
    @load_cmds_list = ['--load', '--load-undir', '--load-dir', '--load-undir-comp', '--load-dir-comp']
    @actions_list = ['--export', '--show-nodes', '--midist-len', '--midist-time', '--center']

    @usage_text = <<-END.gsub(/^ {6}/, '')
      Usage:\truby osm_simple_nav.rb <load_command> <input.IN> <action_command> <action_params> [<debug_commands>]
      \tLoad commands:
      \t\t --load / --load-undir ... load map from file <input.IN> into undirected graph, IN can be ['OSM','XML','DOT']
      \t\t --load-dir ... load map from file <input.IN> into directed graph, IN can be ['OSM','XML','DOT']
      \t\t --load-undir-comp ... load map from file <input.IN> into undirected graph and find largest component, IN can be ['OSM','XML','DOT']
      \t\t --load-dir-comp ... load map from file <input.IN> into directed graph and find largest component, IN can be ['OSM','XML','DOT']
      \tAction commands:
      \t\t --export ... export graph into file; 1 param: <output.OUT> where OUT can be ['PDF','PNG','DOT']
      \t\t --show-nodes ... show list of nodes and their geoposition; no params
      \t\t --show-nodes ... export graph into file, start is green, end is blue; 3 params: start vertex id, end vertex id, <output.OUT> where OUT can be ['PDF','PNG','DOT']
      \t\t --show-nodes ... export graph into file, start is green, end is blue; 5 params: start vertex latitude and longitude, end vertex latitude and longitude, <output.OUT> where OUT can be ['PDF','PNG','DOT']
      \t\t --midist-len ... find shortest path and export graph into file, start is green, end is blue, path is red; 3 params: start vertex id, end vertex id, <output.OUT> where OUT can be ['PDF','PNG','DOT']
      \t\t --midist-len ... find shortest path and export graph into file, start is green, end is blue, path is red; 5 params: start vertex latitude and longitude, end vertex latitude and longitude, <output.OUT> where OUT can be ['PDF','PNG','DOT']
      \t\t --midist-time ... find fastest path and export graph into file, start is green, end is blue, path is red; 3 params: start vertex id, end vertex id, <output.OUT> where OUT can be ['PDF','PNG','DOT']
      \t\t --midist-time ... find fastest path and export graph into file, start is green, end is blue, path is red; 5 params: start vertex latitude and longitude, end vertex latitude and longitude, <output.OUT> where OUT can be ['PDF','PNG','DOT']
      \t\t --center ... find vertices with minimal distance eccentricity, marked in green, only works with --load-undir-comp; 1 param: <output.OUT> where OUT can be ['PDF','PNG','DOT']
      \tDebug commands:
      \t\t --emphesize ... for graphs with largest component: instead of using the largest component only, emphesize edges that do not belong to the largest component
    END

    @dir = false
    @comp = false
  end

  # Prints text specifying its usage
  def usage
    puts @usage_text
  end

  # Command line handling
  def process_args
    # not enough parameters - at least load command, input file and action command must be given
    unless ARGV.length >= 3
      puts "Not enough parameters!"
      puts usage
      exit 1
    end

    # read load command, input file and action command
    @load_cmd = ARGV.shift
    unless @load_cmds_list.include?(@load_cmd)
      puts "Load command not registered!"
      puts usage
      exit 1
    end
    @map_file = ARGV.shift
    unless File.file?(@map_file)
      puts "File #{@map_file} does not exist!"
      puts usage
      exit 1
    end
    @operation = ARGV.shift
    unless @actions_list.include?(@operation)
      puts "Action command not registered!"
      puts usage
      exit 1
    end
    @emphesize = ARGV.include?("--emphesize")
  end

  # Determine type of file given by +file_name+ as suffix.
  #
  # @return [String]
  def file_type(file_name)
    return file_name[file_name.rindex(".")+1,file_name.size]
  end

  # Specify log name to be used to log processing information.
  def prepare_log
    ProcessLogger.construct('log/logfile.log')
  end

  # Load graph from OSM file. This methods loads graph and create +Graph+ as well as +VisualGraph+ instances.
  def load_graph
    graph_loader = GraphLoader.new(@map_file, @highway_attributes, @dir)
    @graph, @visual_graph = graph_loader.load_graph()
  end

  # Load graph from Graphviz file. This methods loads graph and create +Graph+ as well as +VisualGraph+ instances.
  def import_graph
    graph_loader = GraphLoader.new(@map_file, @highway_attributes, @dir)
    @graph, @visual_graph = graph_loader.load_graph_viz
  end

  # Run navigation according to arguments from command line
  def run
    # prepare log and read command line arguments
    prepare_log
    process_args

    # load graph - action depends on last suffix
    case @load_cmd
      when "--load", "--load-undir"
      when "--load-dir"
        @dir = true
      when "--load-undir-comp"
        @comp = true
      when "--load-dir-comp"
        @dir = true
        @comp = true
      else
        usage
        exit 1
    end

    @highway_attributes = ['residential', 'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'unclassified']
    if file_type(@map_file) == "osm" or file_type(@map_file) == "xml" then
      load_graph
    elsif file_type(@map_file) == "dot" or file_type(@map_file) == "gv" then
      import_graph
    else
      puts "Input file type not recognized!"
      usage
    end

    if (@comp)
      @visual_graph.find_largest_component_and_remove_others(@dir, @emphesize)
    end

    # perform the operation
    case @operation
      when '--export'
        out_file = ARGV.shift
        @visual_graph.export_graphviz(out_file)
        return
      when '--show-nodes'
        if (ARGV.size == 0) then
          @visual_graph.show_nodes
          return
        elsif (ARGV.size == 3) then
          start_id = ARGV.shift
          end_id = ARGV.shift
          @visual_graph.mark_start_and_end_using_id(start_id, end_id)
          out_file = ARGV.shift
          @visual_graph.export_graphviz(out_file)
          return
        elsif (ARGV.size == 5) then
          start_lat = ARGV.shift
          start_lon = ARGV.shift
          end_lat = ARGV.shift
          end_lon = ARGV.shift
          @visual_graph.mark_start_and_end_using_lat_lon(start_lat, start_lon, end_lat, end_lon)
          out_file = ARGV.shift
          @visual_graph.export_graphviz(out_file)
          return
        end
      when '--midist-len'
        if (ARGV.size == 3) then
          start_id = ARGV.shift
          end_id = ARGV.shift
          @visual_graph.find_shortest_path_using_id(start_id, end_id)
          out_file = ARGV.shift
          @visual_graph.export_graphviz(out_file)
          return
        elsif (ARGV.size == 5) then
          start_lat = ARGV.shift
          start_lon = ARGV.shift
          end_lat = ARGV.shift
          end_lon = ARGV.shift
          @visual_graph.find_shortest_path_using_lat_lon(start_lat, start_lon, end_lat, end_lon)
          out_file = ARGV.shift
          @visual_graph.export_graphviz(out_file)
          return
        end
      when '--midist-time'
        if (ARGV.size == 3) then
          start_id = ARGV.shift
          end_id = ARGV.shift
          @visual_graph.find_fastest_path_using_id(start_id, end_id)
          out_file = ARGV.shift
          @visual_graph.export_graphviz(out_file)
          return
        elsif (ARGV.size == 5) then
          start_lat = ARGV.shift
          start_lon = ARGV.shift
          end_lat = ARGV.shift
          end_lon = ARGV.shift
          @visual_graph.find_fastest_path_using_lat_lon(start_lat, start_lon, end_lat, end_lon)
          out_file = ARGV.shift
          @visual_graph.export_graphviz(out_file)
          return
        end
      when '--center'
        if (!@dir && @comp)
          @visual_graph.find_center
          out_file = ARGV.shift
          @visual_graph.export_graphviz(out_file)
          return
        end
    end

    usage
    exit 1
  end
end

osm_simple_nav = OSMSimpleNav.new
osm_simple_nav.run
