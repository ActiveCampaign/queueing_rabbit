require 'spec_helper'

describe QueueingRabbit::Worker do
  include_context "StringIO logger"

  subject { QueueingRabbit::Worker }
  let(:class_based_job) {
    Class.new(QueueingRabbit::AbstractJob) do
      def self.perform(payload, metadata); end
    end
  }
  let(:instance_based_job) { Class.new(QueueingRabbit::AbstractJob) }
  let(:creation) {
    Proc.new do
      QueueingRabbit::Worker.new(['QueueingRabbitClassJob', QueueingRabbitInstanceJob])
    end
  }
  let(:worker) { creation.call }

  before do
    stub_const("QueueingRabbitClassJob", class_based_job)
    stub_const("QueueingRabbitInstanceJob", instance_based_job)
  end

  after(:each) do
    QueueingRabbit.client = QueueingRabbit::Client::Bunny
  end

  context 'initialization' do
    context 'when no jobs are provided' do
      before do
        subject.any_instance.should_receive(:fatal)
      end

      it 'raises JobNotPresentError' do
        expect { subject.new([]) }.
               to raise_error(QueueingRabbit::JobNotPresentError)
      end
    end

    context 'when nonexistent job is provided' do
      let(:nonexistent_class_name) { 'SomeNonexistentClassName' }

      before do
        subject.any_instance.should_receive(:fatal)
      end

      it 'raises JobNotFoundError' do
        expect { subject.new([nonexistent_class_name]) }.
               to raise_error(QueueingRabbit::JobNotFoundError)
      end
    end

    context 'when valid job is provided' do
      subject { worker }

      it { should be }
      it { should respond_to(:jobs) }
    end
  end

  context 'instance methods' do
    let(:connection) { double }
    let(:queue) { double }
    let(:payload) { double }
    let(:metadata) { double }

    subject { worker }

    describe '#work' do
      before do
        QueueingRabbit.stub(:connection).and_return(connection)
        [class_based_job, instance_based_job].each do |job|
          QueueingRabbit.should_receive(:follow_job_requirements).
                         with(job).
                         and_yield(nil, nil, queue)
          connection.should_receive(:listen_queue).
                     with(queue, job.listening_options).
                     and_yield(payload, metadata)
        end

        class_based_job.should_receive(:perform).with(payload, metadata)
        instance_based_job.should_receive(:new).
                           with(payload, metadata).
                           and_return(double(:perform => nil))
      end

      it 'listens to queues specified by jobs' do
        subject.work
      end

      it 'writes to the log' do
        subject.should_receive(:info).twice
        subject.work
      end

      describe '#work!' do
        it 'runs #work and joins the connection thread' do
          QueueingRabbit.should_receive(:begin_worker_loop).and_yield
          subject.work!
        end
      end
    end

    describe "#use_pidfile" do
      let(:file_name) { double }
      let(:file) { double }

      context 'given pidfile is already in use' do

        it 'raises a worker error' do
          File.stub(:exist?).with(file_name).and_return(true)
          File.should_receive(:read).with(file_name).and_return('123')
          Process.should_receive(:getpgid).with(123).and_return(123)
          expect { subject.use_pidfile(file_name) }.
              to raise_error(QueueingRabbit::Worker::WorkerError)
        end

      end

      context 'given pidfile is not in use' do

        before do
          File.should_receive(:open).with(file_name, 'w').and_yield(file)
          file.should_receive(:<<).with(Process.pid)
        end

        context 'there is an abandoned pidfile' do

          it 'removes the abandoned pidfile and writes pid to a file' do
            File.stub(:exist?).with(file_name).and_return(true)
            File.should_receive(:read).with(file_name).and_return('123')
            Process.should_receive(:getpgid).with(123).and_raise(Errno::ESRCH)
            subject.use_pidfile(file_name)
          end

        end

        context 'new pidfile' do

          it 'creates a pidfile' do
            File.stub(:exist?).with(file_name).and_return(false)
            subject.use_pidfile(file_name)
          end

        end

      end
    end

    describe "#remove_pidfile" do
      let(:file_name) { double }

      before do
        subject.instance_variable_set(:@pidfile, file_name)
        File.should_receive(:exist?).and_return(true)
        File.should_receive(:delete).with(file_name)
      end

      it 'removes previously created pidfile' do
        subject.remove_pidfile
      end
    end

    describe '#invoke_job' do
      let(:payload) { double }
      let(:metadata) { double }

      context 'when an exception occurs' do

        let(:job) { double }
        let(:error) { StandardError.new }

        it 'silences errors and reports them via a global callback' do
          expect(job).to receive(:perform).and_raise(error)
          expect(QueueingRabbit).
              to receive(:trigger_event).with(:consumer_error, error)
          subject.invoke_job(job, payload, metadata)
        end

      end

    end

    describe "#pid" do
      its(:pid) { should == Process.pid }
    end

    describe '#stop' do
      let(:file_name) { double }

      before do
        subject.instance_variable_set(:@pidfile, file_name)
        QueueingRabbit.stub(:connection).and_return(connection)
      end

      context 'when stopped gracefully' do
        it 'closes the connection, removes the pidfile, waits for jobs to finish and reports the event' do
          connection.should_receive(:next_tick).and_yield
          connection.should_receive(:close).and_yield
          worker.mutex_pool.should_receive(:lock)
          QueueingRabbit.should_receive(:trigger_event).with(:consuming_done)
          File.stub(:exist?).with(file_name).and_return(true)
          File.should_receive(:delete).with(file_name)
          subject.stop(QueueingRabbit.connection, true)
        end
      end

      context 'when stopped immediately' do
        it 'closes the connection and removes the pidfile' do
          connection.should_receive(:next_tick).and_yield
          connection.should_receive(:close).and_yield
          File.stub(:exist?).with(file_name).and_return(true)
          File.should_receive(:delete).with(file_name)
          subject.stop
        end
      end
    end

  end
end
