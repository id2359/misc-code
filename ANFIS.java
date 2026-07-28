import java.util.Arrays;

public class ANFIS {
    private double[][] inputs;
    private double[] outputs;
    private int numMembershipFunctions;
    private double[][] membershipParameters;
    private double[] ruleWeights;
    private double[] consequentParameters;
    private int numRules;

    public ANFIS(double[][] inputs, double[] outputs, int numMembershipFunctions) {
        this.inputs = inputs;
        this.outputs = outputs;
        this.numMembershipFunctions = numMembershipFunctions;
        this.numRules = (int) Math.pow(numMembershipFunctions, inputs[0].length);

        // Initialize membership parameters 
        this.membershipParameters = new double[inputs[0].length * numMembershipFunctions][4];
        for (int i = 0; i < membershipParameters.length; i++) {
            Arrays.fill(membershipParameters[i], 1.0);
        }

        // Initialize rule weights 
        this.ruleWeights = new double[numRules];
        Arrays.fill(ruleWeights, 1.0);

        // Initialize consequent parameters (linear parameters for each rule)
        this.consequentParameters = new double[numRules * (inputs[0].length + 1)];
        Arrays.fill(consequentParameters, 1.0);
    }

    // Gaussian Membership Function
    private double gaussianMF(double x, double mean, double sigma) {
        return Math.exp(-0.5 * Math.pow((x - mean) / sigma, 2));
    }

    public double predict(double[] input) {
        double[] layer1 = new double[inputs[0].length * numMembershipFunctions];
        int index = 0;
        for (int i = 0; i < inputs[0].length; i++) {
            for (int j = 0; j < numMembershipFunctions; j++) {
                double[] params = membershipParameters[i * numMembershipFunctions + j];
                layer1[index++] = gaussianMF(input[i], params[0], params[1]);
            }
        }

        double[] layer2 = new double[numRules];
        for (int i = 0; i < numRules; i++) {
            layer2[i] = 1.0;
            for (int j = 0; j < inputs[0].length; j++) {
                int membershipIndex = i % numMembershipFunctions + j * numMembershipFunctions;
                layer2[i] *= layer1[membershipIndex];
            }
        }

        double totalFiringStrength = Arrays.stream(layer2).sum();
        double[] normalizedFiringStrengths = Arrays.stream(layer2).map(x -> x / totalFiringStrength).toArray();

        double output = 0.0;
        for (int i = 0; i < numRules; i++) {
            double ruleOutput = consequentParameters[i * (inputs[0].length + 1)]; // constant term
            for (int j = 0; j < inputs[0].length; j++) {
                ruleOutput += consequentParameters[i * (inputs[0].length + 1) + j + 1] * input[j];
            }
            output += normalizedFiringStrengths[i] * ruleOutput;
        }
        return output;
    }

    // Training method - here we use a simple gradient descent 
    public void train(int numEpochs, double learningRate) {
        for (int epoch = 0; epoch < numEpochs; epoch++) {
            for (int sample = 0; sample < inputs.length; sample++) {
                double predicted = predict(inputs[sample]);
                double error = outputs[sample] - predicted;

                // Update membership parameters (Layer 1)
                // Update rule weights (Layer 3)
                // Update consequent parameters (Layer 5)
                // These would involve backpropagation-like updates, 
                // which for brevity are not implemented here but should follow 
                // the partial derivative of the error with respect to each parameter.
                
                // Example for consequent parameters:
                for (int rule = 0; rule < numRules; rule++) {
                    double normalizedFiring = 1.0 / Arrays.stream(ruleWeights).sum() * ruleWeights[rule];
                    for (int param = 0; param < inputs[0].length + 1; param++) {
                        int index = rule * (inputs[0].length + 1) + param;
                        double update = learningRate * error * normalizedFiring * (param == 0 ? 1 : inputs[sample][param - 1]);
                        consequentParameters[index] += update;
                    }
                }
            }
        }
    }

    public static void main(String[] args) {
        // Example usage
        double[][] trainInputs = {{0.0, 0.0}, {0.0, 1.0}, {1.0, 0.0}, {1.2, 1.0}};
        double[] trainOutputs = {0.0, 1.0, 1.0, 2.2};
        
        ANFIS anfis = new ANFIS(trainInputs, trainOutputs, 2);  // 2 membership functions per input
        anfis.train(1000, 0.01);

        // Test prediction
        double[] testInput = {0.43, 0.02};
        System.out.println("Prediction for " + Arrays.toString(testInput) + ": " + anfis.predict(testInput));
    }
}
