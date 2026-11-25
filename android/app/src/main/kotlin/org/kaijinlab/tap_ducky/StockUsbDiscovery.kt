package org.kaijinlab.tap_ducky

internal data class StockUsbTarget(val gadget: String, val controller: String, val binding: String)

internal object StockUsbDiscovery {
  private val name = Regex("[A-Za-z0-9._-]+")
  private enum class Evidence { UNKNOWN, DEFINED, LINKED }
  private data class Gadget(val name: String, val binding: String, val evidence: Evidence)

  fun select(
    inventory: String,
    preferredController: String?,
    pendingGadget: String?,
    pendingController: String?,
  ): StockUsbTarget {
    val rows = inventory.lineSequence().filter { it.isNotBlank() }.map { it.split(':') }.toList()
    val controllers = rows.filter { it.first() == "udc" }.mapNotNull { it.getOrNull(1) }
      .filter { name.matches(it) && !it.startsWith("dummy_udc") }.toSet()
    val androidController = rows.firstOrNull { it.first() == "android" }?.getOrNull(1)
    val gadgets = rows.filter { it.first() == "gadget" }.map { row ->
      require(row.size == 4 && name.matches(row[1]) && row[1] != "." && row[1] != ".." &&
        (row[2].isEmpty() || name.matches(row[2]))) { "Android reported an unrecognized USB gadget layout." }
      val evidence = when (row[3]) {
        "linked" -> Evidence.LINKED
        "defined" -> Evidence.DEFINED
        else -> Evidence.UNKNOWN
      }
      Gadget(row[1], row[2], evidence)
    }
    require(gadgets.map { it.name }.distinct().size == gadgets.size) { "Android reported duplicate USB gadget names." }

    val requested = if (pendingGadget == null) preferredController else pendingController
    require(requested == null || requested in controllers) { "The selected USB device controller is unavailable." }
    val nominated = requested ?: androidController?.takeIf { it in controllers }
    val stock = gadgets.filter { it.evidence != Evidence.UNKNOWN }
    val gadget = if (pendingGadget != null) {
      requireNotNull(stock.singleOrNull { it.name == pendingGadget }) { "The saved Android USB gadget is unavailable." }
    } else {
      val bound = if (nominated == null) stock.filter { it.binding in controllers }
        else gadgets.filter { it.binding == nominated }
      when {
        bound.size > 1 -> throw IllegalArgumentException("More than one gadget could be Android's USB gadget.")
        bound.size == 1 -> bound.single().also {
          require(it.evidence != Evidence.UNKNOWN) { "The selected controller belongs to an unrecognized USB gadget." }
        }
        else -> {
          require(stock.none { it.binding in controllers }) {
            "The selected controller differs from Android's current USB gadget binding."
          }
          val unbound = stock.filter { it.binding.isEmpty() }
          val strongest = unbound.maxOfOrNull { it.evidence }
          requireNotNull(unbound.singleOrNull { it.evidence == strongest }) {
            "Could not identify a unique Android USB gadget."
          }
        }
      }
    }
    val occupied = gadgets.filter { it.name != gadget.name }.map { it.binding }.toSet()
    val controller = gadget.binding.ifEmpty { nominated ?: (controllers - occupied).singleOrNull().orEmpty() }
    require(controller in controllers && controller !in occupied) { "Could not identify an available USB device controller." }
    require(nominated == null || controller == nominated) { "Android changed the saved USB controller binding." }
    return StockUsbTarget(gadget.name, controller, gadget.binding)
  }
}
