# Load the installed official XSim utility procedures in their own namespace.
# This works around the local Vivado 2025.2 app's missed common-utils load.
# Source once in the Vivado Tcl Console before Run Behavioral Simulation.
# No Vivado installation file or input stimulus file is changed.
package require ::tclapp::xilinx::xsim
namespace eval ::tclapp::xilinx::xsim {
    source -notrace [file join $home common utils.tcl]
}
puts "XSim common Tcl utilities loaded for the current session."
