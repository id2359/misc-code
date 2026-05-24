package com.lmco.atl.protests

import scala.collection.DefaultMap
import scala.collection.mutable.HashMap
import scala.io.Source._
import com.cra.figaro.algorithm.sampling.Importance
import com.cra.figaro.language.Apply
import com.cra.figaro.language.Constant
import com.cra.figaro.language.Element
import com.cra.figaro.language.Flip
import com.cra.figaro.library.atomic.continuous.Uniform
import com.cra.figaro.library.atomic.continuous.Normal
import com.cra.figaro.library.compound.If
import com.cra.figaro.language.Universe
import com.cra.figaro.library.atomic.continuous.Exponential
import org.apache.commons.math3.distribution.NormalDistribution
import com.cra.figaro.algorithm.sampling.MetropolisHastings
import com.cra.figaro.algorithm.sampling.ProposalScheme
import com.cra.figaro.library.atomic.continuous.Normal
import akka.util.Timeout
import java.util.concurrent.TimeUnit
import com.cra.figaro.language._
import annotation.tailrec
import scala.math.{ tan, log, pow, Pi }
import com.cra.figaro.util.{ random, bound }


object SimpleProtests
{
    // The following code was borrowed from Michael Howard of CRA to add a Cauchy distribution
    /**
     * A InverseGamma distribution in which both the alpha and beta parameters are constants.
     * Theta defaults to 1.
     * InverseGamma(k, theta) is (1 / Gamma(k, 1/theta))
     */
    class AtomicNormal(name: Name[Double], mu: Double, scale: Double, collection: ElementCollection)
      extends Element[Double](name, collection) with Atomic[Double] {
      type Randomness = Double

      def generateRandomness() = {
        tan(random.nextDouble()*Pi)    
      }

      def generateValue(rand: Randomness) = mu + scale*rand

      /**
       * Density of a value.
       */
      def density(x: Double) = {
        (1.0/Pi/scale)*(1.0 / (1 + pow((x-mu)/scale, 2.0)))  
      }

      override def toString =
        "Cauchy(" + mu + ", " + scale + ")"
    }

    object Cauchy extends Creatable {
      /**
       * Create a Normal element in which both mu and scale parameters are constants. 
       */
      def apply(mu: Double, scale: Double)(implicit name: Name[Double], collection: ElementCollection) =
        new AtomicNormal(name, mu, scale, collection)

      type ResultType = Double

      def create(args: List[Element[_]]) = apply(args(0).asInstanceOf[Double], args(1).asInstanceOf[Double])
    }
    // End of Cauchy code
    
    /**
     * This is the abstract model for a single week.
     * We'll add the details in the individual implementations.
     */
    abstract class WeeklyModel 
    {
        // Has there been an event to trigger a protest? (0.0 or 1.0)
        val trigger : Element[Double] 
        
        // The disposition of the people towards protest
        val sentiment : Element[Double]
        
        // The intensity of the government's actions
        val govtall : Element[Double]
        
        // A count of hostile actions by the government
        val hostile : Element[Double]
        
        // The intensity of the people's actions
        val alltgov : Element[Double]
        
        // Number of protests
        val protests : Element[Double]
        
        // Number of weeks of consecutive high protest
        val consecutiveHighProtest : Element[Double] 
    }

    /**
     * These are the parameter's we're going to try to learn.
     * Most of them are coefficients of a linear combination
     */
    abstract class Parameters
    {
        // For Sendiment
        val sent2sent : Element[Double]
        val govtall2sent : Element[Double]
        val hostile2sent : Element[Double]
        val alltgov2sent : Element[Double]
        val consecutiveHighProtest2sent : Element[Double]
        
        // Protests
        val sent2protests : Element[Double]
        
        // Government 
        val protests2govtall : Element[Double]
        val alltgov2govtall : Element[Double]
        val protests2hostile : Element[Double]
        
        // People
        val govtall2alltgov : Element[Double]
        val hostile2alltgov : Element[Double]
        
        // Threshold - this is the number of protests we consider "High"
        val highProtestThreshold : Element[Double]
        
        // Triggers - How much a trigger affects sentiment
        val trigger2sent : Element[Double]
        
        /**
         * Produce a list. We'll need this for training.
         */
        def toList() : List[Element[Double]] 
    }

    /**
     * The parameters for the Prior distribution.
     * They'll all have distributions to sample from.
     */
    class PriorParameters extends Parameters
    {
        // Sentiment
        val sent2sent = Cauchy( 1.0, 0.3 )
        val govtall2sent = Cauchy( -1.0, 2.0 )
        val hostile2sent = Cauchy( 1.0, 2.0 )
        val alltgov2sent = Cauchy( -1.0, 2.0 )
        val consecutiveHighProtest2sent = Cauchy( 30.0, 10.0 )
        
        // protests
        val sent2protests = Cauchy( 30.0, 10.0 )
        
        // Government 
        val protests2govtall = Cauchy( -30.0, 10.0 )
        val alltgov2govtall = Cauchy( 1.0, 2.0 )
        val protests2hostile = Cauchy( 1.0, 2.0 )
        
        // People
        val govtall2alltgov = Cauchy( 1.0, 3.0 )
        val hostile2alltgov = Cauchy( 5.0, 5.0 )
        
        // Threshold
        val highProtestThreshold = Cauchy( 30.0, 10.0 )
        
        // Triggers
        val trigger2sent = Cauchy( 10.0, 3.0 )
        
        /**
         * This is just a list of the parameters
         */
        def toList() = List(       
        // Sentiment
         sent2sent ,
         govtall2sent ,
         hostile2sent ,
         alltgov2sent ,
         consecutiveHighProtest2sent ,
        
        // protests
         sent2protests ,
        
        // Government 
         protests2govtall ,
         alltgov2govtall ,
         protests2hostile ,
        
        // People
         govtall2alltgov ,
         hostile2alltgov ,
        
        // Threshold
         highProtestThreshold ,
        
        // Triggers
         trigger2sent 
     ) 
    }

    /**
     * These are the Learned parameters.
     * They're just constants, fat-fingered in.
     */
    class LearnedParameters extends Parameters
    {
          // Sentiment
        val sent2sent = Constant(1.3677075485827346)
        val govtall2sent = Constant(43.816705101176794)
        val hostile2sent = Constant(1.3705215838506093)
        val alltgov2sent = Constant(-0.30241081905766826)
        val consecutiveHighProtest2sent = Constant(42.377031937327615)
        
        // protests
        val sent2protests = Constant(30.869314384095745)
        
        // Government 
        val protests2govtall = Constant(-19.542948727635462)
        val alltgov2govtall = Constant(2.574871223029797)
        val protests2hostile = Constant(-5.9124152162747405)
        
        // People
        val govtall2alltgov = Constant(29.32142628155293)
        val hostile2alltgov = Constant(3.272390543018787)
        
        // Threshold
        val highProtestThreshold = Constant(23.695876311150947)
        
        // Triggers
        val trigger2sent = Constant(12.330984097687368)

        def toList() = List()
    }

    /**
     * This is the model for the first week.
     * We don't have a previous week, so they're all just distributions.
     */
    class FirstWeeklyModel extends WeeklyModel
    {
          val trigger = Constant(0.0)
          val sentiment = Normal( 0.0, 15.0 )
          val govtall = Normal( -257.8, 273.477  )
          val hostile = Exponential( 0.04 )
          val alltgov = Normal( -117.2, 175.0 )
          val protests = Exponential( 0.04 )
          val consecutiveHighProtest = Normal( 30.0, 10.0 )
    }

    /**
     * This is the model for weeks that have a previous week. This is really the heart of the model.
     * 
     * @param previous Model of the previous week
     * @param params Model parameters
     */
    class MiddleWeeklyModel( previous : WeeklyModel, params : Parameters ) extends WeeklyModel
    {
        /**
         * This is a linear combination of two lists, with a little error thrown in.
         * If the lists are (a,b,c) and (d,e,f), then this will produce
         * a*d + b*e + c*f + Normal(0,3)
         * 
         * @param prevs Values from previous week
         * @param parms Linear coefficients 
         * 
         * @return A linear combination of prevs and parms, plus Normal(0,3)
         */
        def linear( prevs : List[Element[Double]], parms : List[Element[Double]] ) =
        {
            var mean = prevs.zip(parms).map( pair => Apply( pair._1, pair._2, 
                (a:Double, b:Double)=>(a*b)) ).foldLeft(Constant(0.0): Element[Double])((a,b) => (a++b))
            Chain( mean, (m:Double) => Normal(m, 3.0))
        }
        
        /**
         * This adjusts some base value by value*scale, and adds some error.
         * It returns base + value*scale + Normal(0,3)
         * 
         * @param base A base value
         * @param value An adjustment to the base
         * @param scale A scaling factor for the adjustment
         * 
         * @return base+value*scale+Normal(0,3)
         */
        def adjust( base : Element[Double], value : Element[Double], scale : Element[Double] ) =
        {
           var mean = Apply( base, value, scale, (b:Double, v:Double, s:Double ) => (b+v*s) )     
           Chain( mean, (m:Double) => Normal(m, 3.0))
        }
        
        // Triggers are very unlikely
        val trigger = Select( 0.00001 -> 1.0, 0.99999 -> 0.0 );
        
        // The number of consecutive hight protests.
        // If the previous week's protests were high, add one to the previous count.
        // Otherwise, it's 0
        val consecutiveHighProtest = If( Apply(previous.protests,  params.highProtestThreshold, (a:Double, b:Double)=>(a>b)), 
            previous.consecutiveHighProtest++Constant(1.0) , Constant(0.0) )
           
        // Sentiment
        val sentiment = linear( 
            List(previous.sentiment, previous.govtall, previous.alltgov, previous.hostile, consecutiveHighProtest, trigger ),
            List(params.sent2sent, params.govtall2sent, params.alltgov2sent, params.hostile2sent, params.consecutiveHighProtest2sent, params.trigger2sent )
        )
      
        // Government
        val govtall = linear( 
            List( previous.protests, previous.alltgov ),
            List( params.protests2govtall, params.alltgov2govtall )
        )
        
        // People
        val alltgov = linear(
            List( previous.govtall, previous.hostile ),
            List( params.govtall2alltgov, params.hostile2alltgov )
        )
        
        // Hostile events
        val hostile = adjust( previous.hostile, previous.protests, params.protests2hostile )
        
        // Protests, plus some error
        val pmean = Apply( sentiment, params.sent2protests, (a:Double, b:Double) => (a*b))    
        val protests = Chain( pmean, (x:Double) => Normal( x, 3.0 ) )
    }

    /**
     * This is the overall model - all of the weeks together.
     * 
     * @param params The model parameters, wither Prior or Learned
     * @param size The number of weeks
     * @param training True if Training, False if Predicting
     */
    class OverallModel( params : Parameters, size : Int, training : Boolean )
    {
        // Save these things
        val length = size 
        val parms = params
        
        // Build an array of Weekly models
        val weeks : Array[WeeklyModel] = new Array[WeeklyModel](size)
        weeks(0) = new FirstWeeklyModel
        weeks(1) = new MiddleWeeklyModel( weeks(0), params )
        
        // For Training, we'll need them all.
        // For predicting, we'll just set the parameters for week 0 and predict for week 1
        if( training ) for( i <- 2 until size )
        {
            weeks(i) = new MiddleWeeklyModel( weeks(i-1), params ) 
        }   

        // The rest of the code in this class is all about observing values.
        // This is a little tricky, for a couple fo reasons.
        // First, since we're working in Doubles, we can't use observe.
        // In a continuous, real-numbered distribution, the probability
        // of any particular point value is 0. 
        // So, we've got to assert the data via constraints.
        //
        // Some of our numbers and differences get huge, so we'll use
        // a trick. We'll use the log of the pdf of a Normal(0,20) at
        // the different between the actual and the observer.
        val dist = new NormalDistribution( 0.0, 20.0 )
        
        /**
         * This function encapsulates our constraint strategy.
         * 
         * @param observed Data value observed
         * @param actual Value from our Bayesian process
         * 
         * @return A value, which is bigger when observed is closer to actual
         */
        def constrainValue(observed: Double, actual: Double) = 
        {
             dist.logDensity( observed-actual )   
        }
        
        /**
         * Observe a week's data
         * 
         * @param i Week number
         * @param values A HashMap holding observed values
         * @param istrigger True if there was a trigger event this week
         */
        def populate( i : Int, values : HashMap[Symbol,Double], istrigger : Boolean )
        {
            println( "Populating row " + i );
            weeks(i).govtall.removeConstraints()
            weeks(i).alltgov.removeConstraints()
            weeks(i).hostile.removeConstraints()
            weeks(i).protests.removeConstraints()
            weeks(i).trigger.removeConstraints()

            weeks(i).govtall.setLogConstraint(x => constrainValue(values('govtall),x))
            weeks(i).alltgov.setLogConstraint(x => constrainValue(values('alltgov),x))
            weeks(i).hostile.setLogConstraint(x => constrainValue(values('hostile),x))
            weeks(i).protests.setLogConstraint(x => constrainValue(values('protests),x)) 
            weeks(i).trigger.setLogConstraint(x => constrainValue(if(istrigger) 1.0 else 0.0 ,x))
        }
    }

    /**
     * Parse a row of data.
     * 
     * @param line A line of data from the data file.
     * 
     * @return A HashMap mapping data types (as symbols) to values
     */
    def parserow( line : String ) = 
    {
        val map = new HashMap[Symbol,Double]

        val tokens = line.split(',')

        map( 'govtall ) =  tokens(3).toDouble
        map( 'alltgov ) =  tokens(4).toDouble
        map( 'hostile ) =  tokens(2).toDouble
        map( 'protests ) =  tokens(5).toDouble

        println( "Map: " + map );
        map
    }

    /**
     * Learn the parameters of a model.
     * 
     * @param Model The Model to learn parameters for
     */
    def train( model : OverallModel )
    {
        // First, populate the model with observations
        val lines = fromFile("/home/peval/Desktop/PakData.csv").getLines.toList   
        for( i <- 1 until model.length )
        {
          println( "Populating row " + i )
          model.populate( i-1, parserow( lines(i) ), i==19 || i==168 || i==280 || i==610 || i==710 )  
        }

        // We'll use the Algorithm of Last Resort, Metropolis-Hastings.
        // We'll use it in an open-ended fashion, just letting it run unbounded
        // and checking the learned parameters every 5 minutes.
        val alg = MetropolisHastings( ProposalScheme.default, model.parms.toList:_* )

        // It can take a long, time, so we're upping the timeout
        alg.messageTimeout = new Timeout( 2, TimeUnit.MINUTES )
        alg.start()
        println( "alg started" )
        while(true)
        {
          // Wait 5 minutes. Then, stop the algorithm print the current values of the parameters, then resume.
          Thread.sleep( 300000 )
          alg.stop()
          println( "------------------------------" )
          model.parms.toList.foreach { p => println( "= Constant(" + alg.expectation(p, (x:Double)=>x) + ")" ) }
          alg.resume()
        }    
        // No need for alg.kill() - this is an infinite loop. 
    }

    /**
     * Predict a week's protests
     * 
     * @param model The Model
     * @param i The week to predict
     * @param values The week's observed values
     */
    def predict( model : OverallModel, i : Int, values : HashMap[Symbol,Double] )
    {
        // Run M-H 50000 times, predict protests
        // We'll reuse week(0) and week(1), always observing week(0) and predicting week(1)
        val alg = MetropolisHastings( 50000, ProposalScheme.default, model.weeks(1).protests )      
        alg.start()
        alg.stop()
        println( "predicted: " + alg.expectation(model.weeks(1).protests, (x:Double)=>x) + ", actual: " + values.get('protests) )
        alg.kill()

        // Prepare for the next prediction by observing the data values in week(0)
        // The weeks with trigger events are hard-coded.
        model.populate( 0, values, i==19 || i==168 || i==280 || i==610 || i==710 )
    }

    /**
     * The main!
     * 
     * @param args Command-line args, not used.
     */
    def main(args: Array[String])
    {
        // This is for training. We'll use the first 2 years (104 weeks)
        // train() goes into an infinite loop, so for prediction, 
        // comment these 3 lines out.
        val params = new PriorParameters
        val model = new OverallModel( params, 104, true )     
        train( model )    

        // This is for prediction.
        val learned = new LearnedParameters
        val learnedmodel = new OverallModel( learned, 2, false )

        // Read and populate the first line
        // (which will be week 104, since weeks 0-103 were used for learning)
        val lines = fromFile("/home/peval/Desktop/PakData.csv").getLines.toList   
        learnedmodel.populate(0, parserow(lines(104)), false )

        // And, predict a bunch more weeks.
        for( i <- 1 until 100 )
        {
          predict( learnedmodel, i, parserow(lines(i+104))) 
        }
    }
}