package com.lmco.atl.protests

import akka.util.Timeout
import com.cra.figaro.algorithm.sampling.{MetropolisHastings, ProposalScheme}
import com.cra.figaro.language._
import com.cra.figaro.library.atomic.continuous.{Exponential, Normal}
import com.cra.figaro.library.compound.If
import com.cra.figaro.util.random
import org.apache.commons.math3.distribution.NormalDistribution

import java.util.concurrent.TimeUnit
import scala.collection.mutable.ListBuffer
import scala.io.Source
import scala.math.{Pi, pow, tan}

object SimpleProtestsImproved {
  private val DefaultTriggerWeeks = Set(19, 168, 280, 610, 710)
  private val ObservationStdDev = 20.0
  private val ProcessStdDev = 3.0

  case class WeekData(
      govtall: Double,
      alltgov: Double,
      hostile: Double,
      protests: Double
  )

  /**
   * A Cauchy distribution with constant location and scale parameters.
   *
   * The original version called this AtomicNormal even though it implemented a
   * Cauchy distribution. The sampler uses tan(Pi * (u - 0.5)), the standard
   * inverse-CDF form for a standard Cauchy random variable.
   */
  class AtomicCauchy(
      name: Name[Double],
      mu: Double,
      scale: Double,
      collection: ElementCollection
  ) extends Element[Double](name, collection)
      with Atomic[Double] {
    require(scale > 0.0, "Cauchy scale must be positive")

    type Randomness = Double

    def generateRandomness(): Double =
      tan(Pi * (random.nextDouble() - 0.5))

    def generateValue(rand: Randomness): Double =
      mu + scale * rand

    def density(x: Double): Double =
      (1.0 / Pi / scale) * (1.0 / (1.0 + pow((x - mu) / scale, 2.0)))

    override def toString: String =
      "Cauchy(" + mu + ", " + scale + ")"
  }

  object Cauchy {
    def apply(mu: Double, scale: Double)(implicit
        name: Name[Double],
        collection: ElementCollection
    ): AtomicCauchy =
      new AtomicCauchy(name, mu, scale, collection)
  }

  abstract class WeeklyModel {
    val trigger: Element[Double]
    val sentiment: Element[Double]
    val govtall: Element[Double]
    val hostile: Element[Double]
    val alltgov: Element[Double]
    val protests: Element[Double]
    val consecutiveHighProtest: Element[Double]
  }

  abstract class Parameters {
    val sent2sent: Element[Double]
    val govtall2sent: Element[Double]
    val hostile2sent: Element[Double]
    val alltgov2sent: Element[Double]
    val consecutiveHighProtest2sent: Element[Double]

    val sent2protests: Element[Double]

    val protests2govtall: Element[Double]
    val alltgov2govtall: Element[Double]
    val protests2hostile: Element[Double]

    val govtall2alltgov: Element[Double]
    val hostile2alltgov: Element[Double]

    val highProtestThreshold: Element[Double]
    val trigger2sent: Element[Double]

    def namedParameters: List[(String, Element[Double])]

    def toList: List[Element[Double]] =
      namedParameters.map(_._2)
  }

  class PriorParameters extends Parameters {
    val sent2sent = Cauchy(1.0, 0.3)
    val govtall2sent = Cauchy(-1.0, 2.0)
    val hostile2sent = Cauchy(1.0, 2.0)
    val alltgov2sent = Cauchy(-1.0, 2.0)
    val consecutiveHighProtest2sent = Cauchy(30.0, 10.0)

    val sent2protests = Cauchy(30.0, 10.0)

    val protests2govtall = Cauchy(-30.0, 10.0)
    val alltgov2govtall = Cauchy(1.0, 2.0)
    val protests2hostile = Cauchy(1.0, 2.0)

    val govtall2alltgov = Cauchy(1.0, 3.0)
    val hostile2alltgov = Cauchy(5.0, 5.0)

    val highProtestThreshold = Cauchy(30.0, 10.0)
    val trigger2sent = Cauchy(10.0, 3.0)

    def namedParameters: List[(String, Element[Double])] = List(
      "sent2sent" -> sent2sent,
      "govtall2sent" -> govtall2sent,
      "hostile2sent" -> hostile2sent,
      "alltgov2sent" -> alltgov2sent,
      "consecutiveHighProtest2sent" -> consecutiveHighProtest2sent,
      "sent2protests" -> sent2protests,
      "protests2govtall" -> protests2govtall,
      "alltgov2govtall" -> alltgov2govtall,
      "protests2hostile" -> protests2hostile,
      "govtall2alltgov" -> govtall2alltgov,
      "hostile2alltgov" -> hostile2alltgov,
      "highProtestThreshold" -> highProtestThreshold,
      "trigger2sent" -> trigger2sent
    )
  }

  class LearnedParameters extends Parameters {
    val sent2sent = Constant(1.3677075485827346)
    val govtall2sent = Constant(43.816705101176794)
    val hostile2sent = Constant(1.3705215838506093)
    val alltgov2sent = Constant(-0.30241081905766826)
    val consecutiveHighProtest2sent = Constant(42.377031937327615)

    val sent2protests = Constant(30.869314384095745)

    val protests2govtall = Constant(-19.542948727635462)
    val alltgov2govtall = Constant(2.574871223029797)
    val protests2hostile = Constant(-5.9124152162747405)

    val govtall2alltgov = Constant(29.32142628155293)
    val hostile2alltgov = Constant(3.272390543018787)

    val highProtestThreshold = Constant(23.695876311150947)
    val trigger2sent = Constant(12.330984097687368)

    def namedParameters: List[(String, Element[Double])] = List(
      "sent2sent" -> sent2sent,
      "govtall2sent" -> govtall2sent,
      "hostile2sent" -> hostile2sent,
      "alltgov2sent" -> alltgov2sent,
      "consecutiveHighProtest2sent" -> consecutiveHighProtest2sent,
      "sent2protests" -> sent2protests,
      "protests2govtall" -> protests2govtall,
      "alltgov2govtall" -> alltgov2govtall,
      "protests2hostile" -> protests2hostile,
      "govtall2alltgov" -> govtall2alltgov,
      "hostile2alltgov" -> hostile2alltgov,
      "highProtestThreshold" -> highProtestThreshold,
      "trigger2sent" -> trigger2sent
    )
  }

  class FirstWeeklyModel extends WeeklyModel {
    val trigger = Constant(0.0)
    val sentiment = Normal(0.0, 15.0)
    val govtall = Normal(-257.8, 273.477)
    val hostile = Exponential(0.04)
    val alltgov = Normal(-117.2, 175.0)
    val protests = Exponential(0.04)
    val consecutiveHighProtest = Constant(0.0)
  }

  class MiddleWeeklyModel(previous: WeeklyModel, params: Parameters)
      extends WeeklyModel {
    private def noisy(mean: Element[Double]): Element[Double] =
      Chain(mean, (m: Double) => Normal(m, ProcessStdDev))

    private def nonNegative(value: Element[Double]): Element[Double] =
      Apply(value, (x: Double) => math.max(0.0, x))

    def linear(
        prevs: List[Element[Double]],
        parms: List[Element[Double]]
    ): Element[Double] = {
      val mean = prevs
        .zip(parms)
        .map { case (prev, param) =>
          Apply(prev, param, (a: Double, b: Double) => a * b)
        }
        .foldLeft(Constant(0.0): Element[Double])((a, b) => a ++ b)

      noisy(mean)
    }

    def adjust(
        base: Element[Double],
        value: Element[Double],
        scale: Element[Double]
    ): Element[Double] = {
      val mean =
        Apply(base, value, scale, (b: Double, v: Double, s: Double) => b + v * s)
      noisy(mean)
    }

    val trigger = Select(0.00001 -> 1.0, 0.99999 -> 0.0)

    val consecutiveHighProtest = If(
      Apply(
        previous.protests,
        params.highProtestThreshold,
        (protests: Double, threshold: Double) => protests > threshold
      ),
      previous.consecutiveHighProtest ++ Constant(1.0),
      Constant(0.0)
    )

    val sentiment = linear(
      List(
        previous.sentiment,
        previous.govtall,
        previous.alltgov,
        previous.hostile,
        consecutiveHighProtest,
        trigger
      ),
      List(
        params.sent2sent,
        params.govtall2sent,
        params.alltgov2sent,
        params.hostile2sent,
        params.consecutiveHighProtest2sent,
        params.trigger2sent
      )
    )

    val govtall = linear(
      List(previous.protests, previous.alltgov),
      List(params.protests2govtall, params.alltgov2govtall)
    )

    val alltgov = linear(
      List(previous.govtall, previous.hostile),
      List(params.govtall2alltgov, params.hostile2alltgov)
    )

    val hostile =
      nonNegative(adjust(previous.hostile, previous.protests, params.protests2hostile))

    private val protestMean =
      Apply(sentiment, params.sent2protests, (a: Double, b: Double) => a * b)

    val protests =
      nonNegative(noisy(protestMean))
  }

  class OverallModel(params: Parameters, size: Int, training: Boolean) {
    require(size >= 2, "OverallModel requires at least two weeks")

    val length: Int = size
    val parms: Parameters = params
    val weeks: Array[WeeklyModel] = new Array[WeeklyModel](size)

    weeks(0) = new FirstWeeklyModel
    weeks(1) = new MiddleWeeklyModel(weeks(0), params)

    if (training) {
      for (i <- 2 until size) {
        weeks(i) = new MiddleWeeklyModel(weeks(i - 1), params)
      }
    }

    private val observationDistribution =
      new NormalDistribution(0.0, ObservationStdDev)

    def constrainValue(observed: Double, actual: Double): Double =
      observationDistribution.logDensity(observed - actual)

    def populate(weekIndex: Int, data: WeekData, isTrigger: Boolean): Unit = {
      val week = weeks(weekIndex)

      week.govtall.removeConstraints()
      week.alltgov.removeConstraints()
      week.hostile.removeConstraints()
      week.protests.removeConstraints()
      week.trigger.removeConstraints()

      week.govtall.setLogConstraint(x => constrainValue(data.govtall, x))
      week.alltgov.setLogConstraint(x => constrainValue(data.alltgov, x))
      week.hostile.setLogConstraint(x => constrainValue(data.hostile, x))
      week.protests.setLogConstraint(x => constrainValue(data.protests, x))
      week.trigger.setLogConstraint(x => constrainValue(if (isTrigger) 1.0 else 0.0, x))
    }
  }

  private def parseCsvLine(line: String): Vector[String] = {
    val tokens = ListBuffer.empty[String]
    val current = new StringBuilder
    var inQuotes = false
    var i = 0

    while (i < line.length) {
      val char = line.charAt(i)

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line.charAt(i + 1) == '"') {
          current.append('"')
          i += 1
        } else {
          inQuotes = !inQuotes
        }
      } else if (char == ',' && !inQuotes) {
        tokens += current.toString
        current.clear()
      } else {
        current.append(char)
      }

      i += 1
    }

    tokens += current.toString
    tokens.toVector
  }

  def parseRow(line: String): WeekData = {
    val tokens = parseCsvLine(line).map(_.trim)

    if (tokens.length <= 5) {
      throw new IllegalArgumentException(
        "Expected at least 6 CSV columns, found " + tokens.length + ": " + line
      )
    }

    WeekData(
      govtall = tokens(3).toDouble,
      alltgov = tokens(4).toDouble,
      hostile = tokens(2).toDouble,
      protests = tokens(5).toDouble
    )
  }

  def loadData(path: String): Vector[WeekData] = {
    val source = Source.fromFile(path)
    val lines =
      try source.getLines().toVector
      finally source.close()

    lines.zipWithIndex.flatMap { case (line, index) =>
      val trimmed = line.trim

      if (trimmed.isEmpty) {
        None
      } else {
        try {
          Some(parseRow(line))
        } catch {
          case _: NumberFormatException if index == 0 =>
            None
        }
      }
    }
  }

  def train(
      model: OverallModel,
      csvPath: String,
      triggerWeeks: Set[Int],
      checkpointMinutes: Double,
      maxCheckpoints: Int
  ): Unit = {
    val data = loadData(csvPath)
    val weeksToUse = math.min(model.length, data.length)

    for (weekIndex <- 0 until weeksToUse) {
      model.populate(weekIndex, data(weekIndex), triggerWeeks.contains(weekIndex))
    }

    val alg = MetropolisHastings(ProposalScheme.default, model.parms.toList: _*)
    alg.messageTimeout = new Timeout(2, TimeUnit.MINUTES)

    alg.start()

    try {
      var checkpoint = 0

      while (maxCheckpoints <= 0 || checkpoint < maxCheckpoints) {
        Thread.sleep((checkpointMinutes * 60.0 * 1000.0).toLong)
        alg.stop()
        checkpoint += 1

        println("------------------------------")
        println("Checkpoint " + checkpoint)
        model.parms.namedParameters.foreach { case (name, parameter) =>
          val expected = alg.expectation(parameter, (x: Double) => x)
          println("val " + name + " = Constant(" + expected + ")")
        }

        if (maxCheckpoints <= 0 || checkpoint < maxCheckpoints) {
          alg.resume()
        }
      }
    } finally {
      alg.kill()
    }
  }

  def predict(
      model: OverallModel,
      absoluteWeekIndex: Int,
      data: WeekData,
      triggerWeeks: Set[Int]
  ): Unit = {
    val alg = MetropolisHastings(50000, ProposalScheme.default, model.weeks(1).protests)

    alg.start()
    alg.stop()

    val expectedProtests = alg.expectation(model.weeks(1).protests, (x: Double) => x)
    println(
      "week: " + absoluteWeekIndex +
        ", predicted: " + expectedProtests +
        ", actual: " + data.protests
    )

    alg.kill()
    model.populate(0, data, triggerWeeks.contains(absoluteWeekIndex))
  }

  def runPrediction(
      csvPath: String,
      startWeek: Int,
      count: Int,
      triggerWeeks: Set[Int]
  ): Unit = {
    val data = loadData(csvPath)

    if (startWeek < 0 || startWeek >= data.length) {
      throw new IllegalArgumentException(
        "startWeek must be between 0 and " + (data.length - 1)
      )
    }

    val learnedModel = new OverallModel(new LearnedParameters, 2, training = false)
    learnedModel.populate(0, data(startWeek), triggerWeeks.contains(startWeek))

    val endExclusive = math.min(data.length, startWeek + count)
    for (weekIndex <- startWeek + 1 until endExclusive) {
      predict(learnedModel, weekIndex, data(weekIndex), triggerWeeks)
    }
  }

  private def usage: String =
    """Usage:
      |  train <csvPath> [trainingWeeks=104] [checkpointMinutes=5.0] [maxCheckpoints=1]
      |  predict <csvPath> [startWeek=104] [count=100]
      |
      |Use maxCheckpoints <= 0 for open-ended training.
      |""".stripMargin

  def main(args: Array[String]): Unit = {
    args.toList match {
      case "train" :: csvPath :: rest =>
        val trainingWeeks = rest.headOption.map(_.toInt).getOrElse(104)
        val checkpointMinutes = rest.drop(1).headOption.map(_.toDouble).getOrElse(5.0)
        val maxCheckpoints = rest.drop(2).headOption.map(_.toInt).getOrElse(1)
        val model = new OverallModel(new PriorParameters, trainingWeeks, training = true)

        train(
          model,
          csvPath,
          DefaultTriggerWeeks,
          checkpointMinutes,
          maxCheckpoints
        )

      case "predict" :: csvPath :: rest =>
        val startWeek = rest.headOption.map(_.toInt).getOrElse(104)
        val count = rest.drop(1).headOption.map(_.toInt).getOrElse(100)
        runPrediction(csvPath, startWeek, count, DefaultTriggerWeeks)

      case _ =>
        println(usage)
    }
  }
}
